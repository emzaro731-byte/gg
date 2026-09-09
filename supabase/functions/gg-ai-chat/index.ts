import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY") || "";
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") || "openai/gpt-oss-120b";
const AI_API_URL = (Deno.env.get("MY_AI_API_URL") || "").replace(/\/$/, "");
const AI_API_KEY = Deno.env.get("MY_AI_API_KEY") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");

const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
function jsonResponse(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }
function text(value: unknown, max = 12000): string { return typeof value === "string" ? value.trim().slice(0, max) : ""; }
function modeInstruction(mode: string): string {
  const instructions: Record<string, string> = { Chat: "Act as a versatile general-purpose assistant.", Code: "Act as an expert software engineer. Produce complete, correct, runnable code.", Debug: "Act as a senior debugging engineer. Diagnose the root cause first, then provide a concrete fix and verification steps.", Explain: "Act as an expert technical teacher. Explain concepts clearly from first principles with practical examples.", Study: "Act as a patient tutor. Teach progressively and use examples.", Write: "Act as a professional writing assistant. Produce polished, usable text.", Creative: "Act as a creative partner. Generate original ideas and polished creative content." };
  return instructions[mode] || instructions.Chat;
}
const BASE_SYSTEM_PROMPT = `You are GG AI, the intelligent AI assistant built into GG Messenger. Give accurate, useful and natural answers. Understand conversation context. Help with programming, mathematics, science, writing, business, education, technology and creative work. For code, provide complete practical solutions. For debugging, reason from supplied evidence. Never claim to have performed an action you did not perform. Never invent sources, facts, links or tool results. Use Markdown when useful. You are GG AI, not ChatGPT or OpenAI.`;

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
    let input = Array.isArray(body?.messages) ? body.messages : [];
    if (input.length === 0 && typeof body?.message === "string" && body.message.trim()) input = [{ role: "user", content: body.message.trim() }];
    const messages = input.filter((m: any) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string").slice(-80).map((m: any) => ({ role: m.role, content: text(m.content, 24000) })).filter((m: any) => m.content.length > 0);
    if (!messages.length) return jsonResponse({ error: "No valid messages were provided." }, 400);
    const mode = text(body?.mode, 80) || "Chat";
    const project = text(body?.project, 200);
    const context = text(body?.context, 10000);
    const systemParts = [BASE_SYSTEM_PROMPT, `Current mode: ${mode}. ${modeInstruction(mode)}`, project ? `Active project: ${project}.` : "", context ? `Additional trusted app context:\n${context}` : ""].filter(Boolean);
    const selectedModel = text(body?.model, 120) || GROQ_MODEL;
    const codingMode = mode === "Code" || mode === "Debug" || mode === "Explain";
    const temperature = typeof body?.temperature === "number" ? Math.min(Math.max(body.temperature, 0), 2) : codingMode ? 0.2 : 0.7;
    const maxTokens = typeof body?.max_tokens === "number" ? Math.min(Math.max(body.max_tokens, 256), 16384) : codingMode ? 12288 : 8192;
    const payload = { model: selectedModel, messages: [{ role: "system", content: systemParts.join("\n\n") }, ...messages], temperature, max_tokens: maxTokens };

    // Groq is the primary provider. If it is unavailable or errors, fall back to the self-hosted API.
    if (GROQ_API_KEY) {
      const groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${GROQ_API_KEY}` }, body: JSON.stringify({ ...payload, reasoning_effort: codingMode ? "high" : "medium" }) });
      const raw = await groqResponse.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
      if (groqResponse.ok) {
        const reply = data?.choices?.[0]?.message?.content?.toString().trim();
        if (reply) return jsonResponse({ reply, model: data?.model || selectedModel, provider: "groq", user_id: user.id, mode, usage: data?.usage ?? null });
      } else console.error("Groq failed; trying self-hosted fallback:", groqResponse.status, data?.error?.message || raw);
    }

    if (!AI_API_URL || !AI_API_KEY) return jsonResponse({ error: "Groq is unavailable and MY_AI_API_URL/MY_AI_API_KEY is not configured for fallback." }, 503);
    const aiResponse = await fetch(`${AI_API_URL}/v1/chat/completions`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${AI_API_KEY}` }, body: JSON.stringify({ ...payload, model: text(body?.fallback_model, 120) || "default", stream: false }) });
    const raw = await aiResponse.text(); let data: any = null; try { data = JSON.parse(raw); } catch (_) {}
    if (!aiResponse.ok) return jsonResponse({ error: data?.error?.message || data?.detail || raw || `AI fallback returned HTTP ${aiResponse.status}.`, status: aiResponse.status }, aiResponse.status);
    const reply = data?.choices?.[0]?.message?.content?.toString().trim();
    if (!reply) return jsonResponse({ error: "Both AI providers returned no response." }, 502);
    return jsonResponse({ reply, model: data?.model || "default", provider: "my-ai-api-fallback", user_id: user.id, mode, usage: data?.usage ?? null });
  } catch (error) { console.error("GG AI function error:", error); return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected server error." }, 500); }
});
