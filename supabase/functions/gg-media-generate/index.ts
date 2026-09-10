import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const KIE_API_KEY = Deno.env.get("KIE_API_KEY") || "";
const KIE_BASE_URL = "https://api.kie.ai";
const AI_API_URL = (Deno.env.get("MY_AI_API_URL") || "").replace(/\/$/, "");
const AI_API_KEY = Deno.env.get("MY_AI_API_KEY") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
function jsonResponse(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }
function clean(value: unknown, max = 12000): string { return typeof value === "string" ? value.trim().slice(0, max) : ""; }
function safeObject(value: unknown): Record<string, unknown> { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function outputUrl(data: any): string | null {
  const candidates = [data?.data?.response?.resultUrls?.[0], data?.data?.response?.resultUrl, data?.data?.response?.videoUrl, data?.data?.response?.audioUrl, data?.data?.response?.imageUrl, data?.data?.resultUrls?.[0], data?.data?.resultUrl, data?.data?.videoUrl, data?.data?.audioUrl, data?.data?.imageUrl, data?.data?.url, data?.url, data?.data?.response?.result?.[0]];
  for (const value of candidates) if (typeof value === "string" && value.startsWith("http")) return value;
  return null;
}
async function kieFetch(path: string, init: RequestInit = {}) {
  return fetch(`${KIE_BASE_URL}${path}`, { ...init, headers: { "Authorization": `Bearer ${KIE_API_KEY}`, "Content-Type": "application/json", ...(init.headers || {}) } });
}
async function createKie(type: string, model: string, prompt: string, input: Record<string, unknown>) {
  if (type === "music") {
    const customMode = input.customMode !== false;
    const payload = { model: model || "V5_5", customMode, instrumental: input.instrumental === true, callBackUrl: input.callBackUrl || undefined, prompt: input.prompt || prompt, style: input.style || "", title: input.title || "GG AI Song", duration: input.duration || undefined, vocalGender: input.vocalGender || undefined };
    const response = await kieFetch("/api/v1/generate", { method: "POST", body: JSON.stringify(payload) });
    return { response, endpoint: "/api/v1/generate" };
  }
  if (model === "runway") {
    const response = await kieFetch("/api/v1/runway/generate", { method: "POST", body: JSON.stringify({ prompt, imageUrl: input.imageUrl || undefined, aspectRatio: input.aspectRatio || "16:9", duration: input.duration || 5, quality: input.quality || "720p", waterMark: input.waterMark || "" }) });
    return { response, endpoint: "/api/v1/runway/generate" };
  }
  const payload = { model, input: { prompt, ...input } };
  const response = await kieFetch("/api/v1/jobs/createTask", { method: "POST", body: JSON.stringify(payload) });
  return { response, endpoint: "/api/v1/jobs/createTask" };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Only POST requests are supported." }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return jsonResponse({ error: "Authentication required." }, 401);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return jsonResponse({ error: "Supabase authentication is not configured." }, 500);
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Invalid or expired session." }, 401);
    const body = await req.json();
    const action = clean(body?.action, 30) || "create";
    const provider = clean(body?.provider, 30) || "kie";
    if (action === "status") {
      const taskId = clean(body?.task_id, 300);
      if (!taskId) return jsonResponse({ error: "task_id is required." }, 400);
      if (provider !== "kie" || !KIE_API_KEY) return jsonResponse({ error: "KIE task status requires KIE_API_KEY." }, 503);
      const response = await kieFetch(`/api/v1/jobs/getTaskDetails?taskId=${encodeURIComponent(taskId)}`);
      const raw = await response.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
      if (!response.ok) return jsonResponse({ error: data?.msg || data?.error?.message || raw || `KIE status returned HTTP ${response.status}.` }, response.status);
      return jsonResponse({ ...data, output_url: outputUrl(data), user_id: user.id });
    }
    const type = clean(body?.type, 30);
    const prompt = clean(body?.prompt);
    const model = clean(body?.model, 160);
    const input = safeObject(body?.input);
    if (!["image", "video", "music"].includes(type)) return jsonResponse({ error: "type must be image, video, or music." }, 400);
    if (!prompt && type !== "music") return jsonResponse({ error: "A prompt is required." }, 400);
    if (!model) return jsonResponse({ error: "A model is required." }, 400);

    if (provider === "kie") {
      if (!KIE_API_KEY) return jsonResponse({ error: "KIE is not configured. Add KIE_API_KEY to Supabase Edge Function secrets." }, 503);
      const { response, endpoint } = await createKie(type, model, prompt, input);
      const raw = await response.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
      if (!response.ok) return jsonResponse({ error: data?.msg || data?.error?.message || raw || `KIE returned HTTP ${response.status}.`, code: data?.code ?? response.status }, response.status);
      const taskId = data?.data?.taskId || data?.taskId || data?.data?.task_id;
      const url = outputUrl(data);
      return jsonResponse({ provider: "kie", type, model, task_id: taskId || null, output_url: url, response: data, endpoint, user_id: user.id });
    }

    if (provider === "existing-api") {
      if (!AI_API_URL || !AI_API_KEY) return jsonResponse({ error: "Existing AI API is not configured." }, 503);
      const endpoint = type === "image" ? "/v1/images/generations" : type === "video" ? "/v1/videos/generations" : "/v1/audio/generations";
      const response = await fetch(`${AI_API_URL}${endpoint}`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${AI_API_KEY}` }, body: JSON.stringify({ model, prompt, ...input }) });
      const raw = await response.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
      if (!response.ok) return jsonResponse({ error: data?.error?.message || data?.detail || raw || `Existing AI API returned HTTP ${response.status}.` }, response.status);
      const item = Array.isArray(data?.data) ? data.data[0] : data?.data;
      const url = item?.url || data?.url || data?.output_url || data?.outputUrl;
      return jsonResponse({ provider: "existing-api", type, model: data?.model || model, output_url: typeof url === "string" ? url : null, task_id: data?.id || data?.task_id || null, response: data, user_id: user.id });
    }
    return jsonResponse({ error: "Unknown provider. Use kie or existing-api." }, 400);
  } catch (error) {
    console.error("GG media function error:", error);
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected server error." }, 500);
  }
});
