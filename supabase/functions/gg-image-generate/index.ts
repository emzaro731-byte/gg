import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAGIC_HOUR_API_KEY = Deno.env.get("MAGIC_HOUR_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function clean(value: unknown, max = 4000): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { status: 200, headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Only POST requests are supported." }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return jsonResponse({ error: "Authentication required." }, 401);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return jsonResponse({ error: "Supabase authentication is not configured." }, 500);
  if (!MAGIC_HOUR_API_KEY) return jsonResponse({ error: "MAGIC_HOUR_API_KEY is not configured in Supabase Function Secrets." }, 503);

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
    const resolution = "640px";

    const createResponse = await fetch("https://api.magichour.ai/v1/ai-image-generator", {
      method: "POST",
      headers: {
        "accept": "application/json",
        "authorization": `Bearer ${MAGIC_HOUR_API_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: `GG Image - ${user.id}`,
        image_count: 1,
        model,
        aspect_ratio: aspectRatio,
        resolution,
        style: { prompt, tool: "ai-anime-generator" },
      }),
    });

    const createRaw = await createResponse.text();
    let created: any = null;
    try { created = JSON.parse(createRaw); } catch (_) {}
    if (!createResponse.ok) {
      const message = created?.message || createRaw || `Magic Hour returned HTTP ${createResponse.status}.`;
      return jsonResponse({ error: message, status: createResponse.status }, createResponse.status);
    }

    const projectId = created?.id?.toString();
    if (!projectId) return jsonResponse({ error: "Magic Hour did not return an image project ID." }, 502);

    // Poll briefly so the Flutter app receives a ready-to-display image URL.
    for (let attempt = 0; attempt < 24; attempt++) {
      await new Promise((resolve) => setTimeout(resolve, 2500));
      const statusResponse = await fetch(`https://api.magichour.ai/v1/image-projects/${encodeURIComponent(projectId)}`, {
        method: "GET",
        headers: { "accept": "application/json", "authorization": `Bearer ${MAGIC_HOUR_API_KEY}` },
      });
      const statusRaw = await statusResponse.text();
      let statusData: any = null;
      try { statusData = JSON.parse(statusRaw); } catch (_) {}
      if (!statusResponse.ok) return jsonResponse({ error: statusData?.message || statusRaw || "Could not check image status." }, statusResponse.status);

      const status = statusData?.status?.toString();
      if (status === "complete") {
        const url = statusData?.downloads?.[0]?.url?.toString();
        if (!url) return jsonResponse({ error: "Image completed but no download URL was returned." }, 502);
        return jsonResponse({ image_url: url, project_id: projectId, model, credits_charged: statusData?.credits_charged ?? created?.credits_charged ?? null, user_id: user.id });
      }
      if (status === "error" || status === "canceled") {
        const message = statusData?.error?.message || `Image generation ${status}.`;
        return jsonResponse({ error: message }, 502);
      }
    }

    return jsonResponse({ error: "Image generation is still processing. Please try again shortly.", project_id: projectId }, 202);
  } catch (error) {
    console.error("GG Magic Hour image function error:", error);
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected server error." }, 500);
  }
});
