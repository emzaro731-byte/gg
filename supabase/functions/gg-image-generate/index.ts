import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAGIC_HOUR_API_KEY = Deno.env.get("MAGIC_HOUR_API_KEY") || "";
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
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) return jsonResponse({ error: "Invalid or expired session." }, 401);
    const body = await req.json();
    const prompt = clean(body?.prompt);
    if (!prompt) return jsonResponse({ error: "Please provide an image prompt." }, 400);
    const allowedModels = new Set(["flux-schnell", "flux-2-klein", "z-image-turbo"]);
    const model = allowedModels.has(clean(body?.model, 80)) ? clean(body?.model, 80) : "flux-schnell";
    const allowedRatios = new Set(["1:1", "16:9", "9:16"]);
    const aspectRatio = allowedRatios.has(clean(body?.aspect_ratio, 20)) ? clean(body?.aspect_ratio, 20) : "1:1";

    // Magic Hour is the primary image provider.
    if (MAGIC_HOUR_API_KEY) {
      try {
        const createResponse = await fetch("https://api.magichour.ai/v1/ai-image-generator", { method: "POST", headers: { "accept": "application/json", "authorization": `Bearer ${MAGIC_HOUR_API_KEY}`, "content-type": "application/json" }, body: JSON.stringify({ name: `GG Image - ${user.id}`, image_count: 1, model, aspect_ratio: aspectRatio, resolution: "640px", style: { prompt, tool: "ai-anime-generator" } }) });
        const createRaw = await createResponse.text(); let created: any = null; try { created = JSON.parse(createRaw); } catch (_) {}
        if (createResponse.ok) {
          const projectId = created?.id?.toString();
          if (projectId) {
            for (let attempt = 0; attempt < 24; attempt++) {
              await new Promise((resolve) => setTimeout(resolve, 2500));
              const statusResponse = await fetch(`https://api.magichour.ai/v1/image-projects/${encodeURIComponent(projectId)}`, { headers: { "accept": "application/json", "authorization": `Bearer ${MAGIC_HOUR_API_KEY}` } });
              const statusRaw = await statusResponse.text(); let statusData: any = null; try { statusData = JSON.parse(statusRaw); } catch (_) {}
              if (!statusResponse.ok) break;
              const status = statusData?.status?.toString();
              if (status === "complete") {
                const url = statusData?.downloads?.[0]?.url?.toString();
                if (url) return jsonResponse({ image_url: url, project_id: projectId, model, provider: "magic-hour", credits_charged: statusData?.credits_charged ?? created?.credits_charged ?? null, user_id: user.id });
                break;
              }
              if (status === "error" || status === "canceled") break;
            }
          }
        }
        console.error("Magic Hour failed or timed out; trying self-hosted image fallback.");
      } catch (error) { console.error("Magic Hour fallback trigger:", error); }
    }

    // Self-hosted image API is the secondary provider.
    if (!AI_API_URL || !AI_API_KEY) return jsonResponse({ error: "Image providers are unavailable. Configure MAGIC_HOUR_API_KEY or MY_AI_API_URL/MY_AI_API_KEY." }, 503);
    const aiResponse = await fetch(`${AI_API_URL}/v1/images/generations`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${AI_API_KEY}` }, body: JSON.stringify({ prompt, size: sizeForRatio(aspectRatio), n: 1, style: styleForModel(model) }) });
    const raw = await aiResponse.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
    if (!aiResponse.ok) return jsonResponse({ error: data?.error?.message || data?.detail || raw || `Image fallback returned HTTP ${aiResponse.status}.`, status: aiResponse.status }, aiResponse.status);
    const item = Array.isArray(data?.data) ? data.data[0] : data?.data;
    const imagePath = item?.url?.toString();
    if (!imagePath) return jsonResponse({ error: "Both image providers returned no image URL." }, 502);
    const imageUrl = imagePath.startsWith("http") ? imagePath : `${AI_API_URL}${imagePath.startsWith("/") ? "" : "/"}${imagePath}`;
    return jsonResponse({ image_url: imageUrl, model: data?.model || model, provider: "my-ai-api-fallback", user_id: user.id });
  } catch (error) { console.error("GG image function error:", error); return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected server error." }, 500); }
});
