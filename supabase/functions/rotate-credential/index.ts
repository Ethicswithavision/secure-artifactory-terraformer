
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RotationRequest {
  credentialId: string;
  trigger: 'manual' | 'scheduled' | 'emergency';
}

interface SecretManager {
  type: string;
  endpoint_url: string | null;
  region: string | null;
  configuration: any;
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

    const { credentialId, trigger }: RotationRequest = await req.json();

    console.log(`Starting rotation for credential ${credentialId} (trigger: ${trigger})`);

    // Create rotation log entry
    const { data: logEntry, error: logError } = await supabase
      .from('rotation_logs')
      .insert({
        credential_id: credentialId,
        rotation_trigger: trigger,
        status: 'in_progress',
        started_at: new Date().toISOString()
      })
      .select()
      .single();

    if (logError) {
      throw new Error(`Failed to create rotation log: ${logError.message}`);
    }

    try {
      // Fetch credential details
      const { data: credential, error: credError } = await supabase
        .from('credentials')
        .select('*')
        .eq('id', credentialId)
        .single();

      if (credError || !credential) {
        throw new Error(`Credential not found: ${credError?.message || 'Unknown error'}`);
      }

      // Get active secret managers
      const { data: secretManagers, error: smError } = await supabase
        .from('secret_managers')
        .select('*')
        .eq('is_active', true);

      if (smError) {
        throw new Error(`Failed to fetch secret managers: ${smError.message}`);
      }

      // Simulate credential rotation based on type
      const newSecretHash = await rotateCredential(credential, secretManagers);

      // Update credential with new rotation info
      const { error: updateError } = await supabase
        .from('credentials')
        .update({
          last_rotated_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        })
        .eq('id', credentialId);

      if (updateError) {
        throw new Error(`Failed to update credential: ${updateError.message}`);
      }

      // Update rotation log as completed
      const { error: logUpdateError } = await supabase
        .from('rotation_logs')
        .update({
          status: 'completed',
          completed_at: new Date().toISOString(),
          new_secret_hash: newSecretHash
        })
        .eq('id', logEntry.id);

      if (logUpdateError) {
        console.error('Failed to update rotation log:', logUpdateError);
      }

      console.log(`Successfully rotated credential ${credentialId}`);

      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Credential rotated successfully',
          logId: logEntry.id
        }),
        { 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200 
        }
      );

    } catch (rotationError) {
      console.error('Rotation failed:', rotationError);

      // Update rotation log as failed
      await supabase
        .from('rotation_logs')
        .update({
          status: 'failed',
          completed_at: new Date().toISOString(),
          error_message: rotationError.message
        })
        .eq('id', logEntry.id);

      throw rotationError;
    }

  } catch (error) {
    console.error('Error in rotate-credential function:', error);
    
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

async function rotateCredential(credential: any, secretManagers: SecretManager[]): Promise<string> {
  console.log(`Rotating ${credential.type} credential: ${credential.name}`);

  // Simulate rotation based on credential type
  switch (credential.type) {
    case 'artifactory_token':
      return await rotateArtifactoryToken(credential, secretManagers);
    case 'service_user_password':
      return await rotateServiceUserPassword(credential, secretManagers);
    case 'ldap_password':
      return await rotateLdapPassword(credential, secretManagers);
    case 'ssl_certificate':
      return await rotateSslCertificate(credential, secretManagers);
    default:
      throw new Error(`Unsupported credential type: ${credential.type}`);
  }
}

async function rotateArtifactoryToken(credential: any, secretManagers: SecretManager[]): Promise<string> {
  // Simulate Artifactory token rotation
  const newToken = generateSecureToken();
  
  // In a real implementation, you would:
  // 1. Call Artifactory API to create new token
  // 2. Store new token in secret manager
  // 3. Update applications to use new token
  // 4. Revoke old token
  
  await storeInSecretManager(credential.external_secret_path, newToken, secretManagers);
  return hashSecret(newToken);
}

async function rotateServiceUserPassword(credential: any, secretManagers: SecretManager[]): Promise<string> {
  // Simulate service user password rotation
  const newPassword = generateSecurePassword();
  
  // In a real implementation, you would:
  // 1. Update password in LDAP/AD
  // 2. Store new password in secret manager
  // 3. Update service configurations
  
  await storeInSecretManager(credential.external_secret_path, newPassword, secretManagers);
  return hashSecret(newPassword);
}

async function rotateLdapPassword(credential: any, secretManagers: SecretManager[]): Promise<string> {
  // Simulate LDAP password rotation
  const newPassword = generateSecurePassword();
  
  // In a real implementation, you would:
  // 1. Update LDAP bind password
  // 2. Store new password in secret manager
  // 3. Update LDAP client configurations
  
  await storeInSecretManager(credential.external_secret_path, newPassword, secretManagers);
  return hashSecret(newPassword);
}

async function rotateSslCertificate(credential: any, secretManagers: SecretManager[]): Promise<string> {
  // Simulate SSL certificate rotation
  const certFingerprint = generateCertificateFingerprint();
  
  // In a real implementation, you would:
  // 1. Generate new certificate
  // 2. Store certificate and key in secret manager
  // 3. Update services to use new certificate
  // 4. Revoke old certificate
  
  await storeInSecretManager(credential.external_secret_path, certFingerprint, secretManagers);
  return hashSecret(certFingerprint);
}

async function storeInSecretManager(path: string, secret: string, secretManagers: SecretManager[]): Promise<void> {
  for (const manager of secretManagers) {
    console.log(`Storing secret in ${manager.type} at path: ${path}`);
    
    // In a real implementation, you would integrate with actual secret managers:
    switch (manager.type) {
      case 'aws_secrets_manager':
        // await storeInAWS(path, secret, manager);
        break;
      case 'hashicorp_vault':
        // await storeInVault(path, secret, manager);
        break;
      case 'azure_key_vault':
        // await storeInAzure(path, secret, manager);
        break;
    }
  }
}

function generateSecureToken(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

function generateSecurePassword(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*';
  let result = '';
  for (let i = 0; i < 16; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

function generateCertificateFingerprint(): string {
  const chars = '0123456789ABCDEF';
  let result = '';
  for (let i = 0; i < 40; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
    if (i % 2 === 1 && i < 39) result += ':';
  }
  return result;
}

async function hashSecret(secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(secret);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}
