// Supabase Edge Function: Send Push Notification via FCM
// Triggered by database webhooks for SOS alerts and geofence events

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const FIREBASE_SERVER_KEY = Deno.env.get('FIREBASE_SERVER_KEY') || ''

interface PushPayload {
    type: 'sos' | 'geofence' | 'schedule'
    childId: string
    parentFcmToken: string
    title: string
    body: string
    data?: Record<string, string>
}

async function sendFcmNotification(
    fcmToken: string,
    title: string,
    body: string,
    data: Record<string, string> = {},
    priority: 'high' | 'normal' = 'high'
): Promise<boolean> {
    if (!FIREBASE_SERVER_KEY) {
        console.error('FIREBASE_SERVER_KEY not configured')
        return false
    }

    const message = {
        to: fcmToken,
        notification: {
            title,
            body,
            sound: priority === 'high' ? 'default' : undefined,
            priority,
        },
        data,
        priority,
        android: {
            priority,
            notification: {
                channel_id: priority === 'high' ? 'parentlock_sos' : 'parentlock_channel',
                sound: 'default',
            },
        },
        apns: {
            payload: {
                aps: {
                    alert: { title, body },
                    sound: 'default',
                    'content-available': 1,
                },
            },
        },
    }

    try {
        const response = await fetch('https://fcm.googleapis.com/fcm/send', {
            method: 'POST',
            headers: {
                'Authorization': `key=${FIREBASE_SERVER_KEY}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(message),
        })

        const result = await response.json()
        console.log('FCM response:', result)
        return result.success === 1
    } catch (error) {
        console.error('FCM send error:', error)
        return false
    }
}

serve(async (req) => {
    // CORS headers
    const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
        'Content-Type': 'application/json',
    }

    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers })
    }

    try {
        const payload: PushPayload = await req.json()
        console.log('Received push request:', payload)

        const { type, parentFcmToken, title, body, data } = payload

        if (!parentFcmToken) {
            return new Response(
                JSON.stringify({ error: 'No FCM token provided' }),
                { status: 400, headers }
            )
        }

        // Set priority based on type
        const priority = type === 'sos' ? 'high' : 'normal'

        const success = await sendFcmNotification(
            parentFcmToken,
            title,
            body,
            { type, ...(data || {}) },
            priority
        )

        return new Response(
            JSON.stringify({ success }),
            { status: success ? 200 : 500, headers }
        )
    } catch (error) {
        console.error('Error processing request:', error)
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers }
        )
    }
})
