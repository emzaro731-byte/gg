import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AI_API_URL = (Deno.env.get("MY_AI_API_URL") || "").replace(/\/$/, "");
const AI_API_KEY = Deno.env.get("MY_AI_API_KEY") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
function jsonResponse(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }
function clean(value: unknown, max = 4000): string { return typeof value === "string" ? value.trim().slice(0, max) : ""; }
function sizeForRatio(ratio: string): string { if (ratio === "16:9") return "1152x648"; if (ratio === "9:16") return "648x1152"; return "1024x1024"; }
function styleForModel(model: string): string { if (model === "flux-schnell") return "photorealistic"; if (model === "flux-2-klein") return "cinematic"; if (model === "z-image-turbo") return "digital-art"; return "none"; }
serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Only POST requests are supported." }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return jsonResponse({ error: "Authentication required." }, 401);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return jsonResponse({ error: "Supabase authentication is not configured." }, 500);
  if (!AI_API_URL || !AI_API_KEY) return jsonResponse({ error: "MY_AI_API_URL or MY_AI_API_KEY is not configured in Supabase Function Secrets." }, 503);
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Invalid or expired session." }, 401);
    const body = await req.json();
    const prompt = clean(body?.prompt);
    if (!prompt) return jsonResponse({ error: "Please provide an image prompt." }, 400);
    const model = clean(body?.model, 80) || "flux-schnell";
    const aspectRatio = clean(body?.aspect_ratio, 20) || "1:1";
    const aiResponse = await fetch(`${AI_API_URL}/v1/images/generations`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${AI_API_KEY}` },
      body: JSON.stringify({ prompt, size: sizeForRatio(aspectRatio), n: 1, style: styleForModel(model) }),
    });
    const raw = await aiResponse.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
    if (!aiResponse.ok) return jsonResponse({ error: data?.error?.message || data?.detail || raw || `My AI API returned HTTP ${aiResponse.status}.`, status: aiResponse.status }, aiResponse.status);
    const item = Array.isArray(data?.data) ? data.data[0] : data?.data;
    const imagePath = item?.url?.toString();
    if (!imagePath) return jsonResponse({ error: "My AI API generated no image URL." }, 502);
    const imageUrl = imagePath.startsWith("http") ? imagePath : `${AI_API_URL}${imagePath.startsWith("/") ? "" : "/"}${imagePath}`;
    return jsonResponse({ image_url: imageUrl, model: data?.model || model, provider: "my-ai-api", user_id: user.id });
  } catch (error) { console.error("GG self-hosted image proxy error:", error); return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected server error." }, 500); }
});
