import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' },
})

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'Missing authorization header' }, 401)

  const groqKey = Deno.env.get('GROQ_API_KEY')
  if (!groqKey) return json({ error: 'GROQ_API_KEY is not configured in Supabase.' }, 500)

  try {
    const body = await req.json()
    const input = Array.isArray(body?.messages) ? body.messages : []
    const messages = input
      .filter((m: any) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
      .slice(-40)
      .map((m: any) => ({ role: m.role, content: m.content.trim().slice(0, 12000) }))
      .filter((m: any) => m.content.length > 0)

    if (!messages.length || messages[messages.length - 1].role !== 'user') return json({ error: 'A user message is required.' }, 400)

    const model = Deno.env.get('GROQ_MODEL') || 'llama-3.3-70b-versatile'
    const systemPrompt = `You are GG AI, the intelligent assistant built into GG Messenger.
Be helpful, natural, accurate, and concise. Remember the conversation context.
Help with writing, coding, explanations, brainstorming, study, planning, and everyday questions.
If the user asks for something unsafe or illegal, refuse briefly and offer a safe alternative.`

    const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${groqKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        messages: [{ role: 'system', content: systemPrompt }, ...messages],
        temperature: 0.65,
        max_tokens: 4096,
      }),
    })

    const data = await groqResponse.json()
    if (!groqResponse.ok) return json({ error: data?.error?.message || 'Groq request failed.' }, groqResponse.status)

    const reply = data?.choices?.[0]?.message?.content?.toString().trim()
    if (!reply) return json({ error: 'GG AI returned an empty response.' }, 502)

    return json({
      reply,
      model,
      usage: data?.usage ?? null,
    })
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unexpected server error.' }, 500)
  }
})
