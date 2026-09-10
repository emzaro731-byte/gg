import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'
const TOKEN_URL = 'https://oauth2.googleapis.com/token'

function base64UrlEncode(value: Uint8Array): string {
  let binary = ''
  for (const byte of value) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function utf8(value: string): Uint8Array {
  return new TextEncoder().encode(value)
}

function pemToBytes(pem: string): Uint8Array {
  const clean = pem.replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\s/g, '')
  const binary = atob(clean)
  return Uint8Array.from(binary, (char) => char.charCodeAt(0))
}

async function getGoogleAccessToken(serviceAccount: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = base64UrlEncode(utf8(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
  const claim = base64UrlEncode(utf8(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: FCM_SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  })))
  const unsigned = `${header}.${claim}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, utf8(unsigned))
  const assertion = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })
  if (!response.ok) throw new Error(`Google OAuth failed: ${await response.text()}`)
  const data = await response.json()
  if (!data.access_token) throw new Error('Google OAuth returned no access token')
  return data.access_token
}

function getSecretKey(): string {
  const raw = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (!raw) throw new Error('SUPABASE_SECRET_KEYS is unavailable')
  try {
    const parsed = JSON.parse(raw)
    const key = parsed.default
    if (typeof key === 'string' && key.length > 0) return key
  } catch (_) {
    // Older Supabase environments may expose the service role key directly.
  }
  throw new Error('No Supabase server secret key found')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: corsHeaders })

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const jwt = authHeader.replace(/^Bearer\s+/i, '').trim()
    if (!jwt) return Response.json({ error: 'Missing authorization' }, { status: 401, headers: corsHeaders })

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serverKey = getSecretKey()
    const admin = createClient(supabaseUrl, serverKey)
    const { data: authData, error: authError } = await admin.auth.getUser(jwt)
    if (authError || !authData.user) return Response.json({ error: 'Unauthorized' }, { status: 401, headers: corsHeaders })

    const body = await req.json()
    const calleeUserId = String(body.callee_user_id ?? '')
    const callId = String(body.call_id ?? '')
    const callerId = String(body.caller_id ?? authData.user.id)
    const callerName = String(body.caller_name ?? 'GG Messenger')
    const callType = body.call_type === 'video' ? 'video' : 'voice'

    if (!calleeUserId || !callId || callerId !== authData.user.id) {
      return Response.json({ error: 'Invalid call payload' }, { status: 400, headers: corsHeaders })
    }

    const { data: tokens, error: tokenError } = await admin
      .from('device_tokens')
      .select('token')
      .eq('user_id', calleeUserId)
      .eq('platform', 'android')

    if (tokenError) throw tokenError
    if (!tokens?.length) return Response.json({ sent: 0, message: 'No registered device token' }, { headers: corsHeaders })

    const firebaseJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON')
    if (!firebaseJson) throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not configured')
    const serviceAccount = JSON.parse(firebaseJson)
    const accessToken = await getGoogleAccessToken(serviceAccount)
    const projectId = serviceAccount.project_id

    let sent = 0
    let removed = 0
    for (const row of tokens) {
      const token = String(row.token)
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: callType === 'video' ? 'Incoming video call' : 'Incoming voice call',
              body: `${callerName} is calling you`,
            },
            data: {
              type: 'call',
              call_id: callId,
              caller_id: callerId,
              caller_name: callerName,
              call_type: callType,
            },
            android: {
              priority: 'HIGH',
              notification: {
                channel_id: 'gg_calls',
                sound: 'default',
                default_vibrate_timings: true,
              },
            },
          },
        }),
      })

      if (response.ok) {
        sent++
        continue
      }

      const errorText = await response.text()
      if (/UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT/i.test(errorText)) {
        await admin.from('device_tokens').delete().eq('token', token)
        removed++
      } else {
        console.error('FCM send failed:', response.status, errorText)
      }
    }

    return Response.json({ sent, removed, total: tokens.length }, { headers: corsHeaders })
  } catch (error) {
    console.error('send-call-push error:', error)
    return Response.json({ error: error instanceof Error ? error.message : 'Internal server error' }, { status: 500, headers: corsHeaders })
  }
})
