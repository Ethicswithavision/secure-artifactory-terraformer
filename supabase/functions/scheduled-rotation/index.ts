
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    console.log('Running scheduled credential rotation check...');

    // Find credentials that need rotation
    const now = new Date().toISOString();
    const { data: credentialsToRotate, error: fetchError } = await supabase
      .from('credentials')
      .select('*')
      .eq('is_active', true)
      .lte('next_rotation_at', now);

    if (fetchError) {
      throw new Error(`Failed to fetch credentials: ${fetchError.message}`);
    }

    console.log(`Found ${credentialsToRotate?.length || 0} credentials needing rotation`);

    const rotationResults = [];

    for (const credential of credentialsToRotate || []) {
      try {
        console.log(`Initiating scheduled rotation for credential: ${credential.name}`);

        // Call the rotation function
        const rotationResponse = await fetch(`${Deno.env.get('SUPABASE_URL')}/functions/v1/rotate-credential`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            credentialId: credential.id,
            trigger: 'scheduled'
          }),
        });

        if (!rotationResponse.ok) {
          throw new Error(`Rotation failed: ${rotationResponse.statusText}`);
        }

        const rotationResult = await rotationResponse.json();
        rotationResults.push({
          credentialId: credential.id,
          credentialName: credential.name,
          success: true,
          logId: rotationResult.logId
        });

        console.log(`Successfully initiated rotation for credential: ${credential.name}`);

      } catch (rotationError) {
        console.error(`Failed to rotate credential ${credential.name}:`, rotationError);
        
        rotationResults.push({
          credentialId: credential.id,
          credentialName: credential.name,
          success: false,
          error: rotationError.message
        });

        // Log the failure
        await supabase
          .from('rotation_logs')
          .insert({
            credential_id: credential.id,
            rotation_trigger: 'scheduled',
            status: 'failed',
            started_at: new Date().toISOString(),
            completed_at: new Date().toISOString(),
            error_message: rotationError.message
          });
      }
    }

    console.log('Scheduled rotation check completed');

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Scheduled rotation check completed',
        credentialsProcessed: credentialsToRotate?.length || 0,
        results: rotationResults
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    );

  } catch (error) {
    console.error('Error in scheduled-rotation function:', error);
    
    return new Response(
      JSON.stringify({
        error: error.message || 'Internal server error'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500
      }
    );
  }
});
