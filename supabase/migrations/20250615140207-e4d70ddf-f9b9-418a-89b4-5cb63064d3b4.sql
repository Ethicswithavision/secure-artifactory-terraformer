
-- Create enum for credential types
CREATE TYPE credential_type AS ENUM ('artifactory_token', 'service_user_password', 'ldap_password', 'ssl_certificate');

-- Create enum for rotation status
CREATE TYPE rotation_status AS ENUM ('pending', 'in_progress', 'completed', 'failed', 'skipped');

-- Create table for storing credential metadata (not the actual secrets)
CREATE TABLE public.credentials (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  type credential_type NOT NULL,
  description TEXT,
  external_secret_path TEXT NOT NULL, -- Path in external secret manager
  rotation_interval_days INTEGER NOT NULL DEFAULT 30,
  expires_at TIMESTAMP WITH TIME ZONE,
  last_rotated_at TIMESTAMP WITH TIME ZONE,
  next_rotation_at TIMESTAMP WITH TIME ZONE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create table for rotation schedules
CREATE TABLE public.rotation_schedules (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  credential_id UUID REFERENCES public.credentials(id) ON DELETE CASCADE NOT NULL,
  cron_expression TEXT NOT NULL, -- e.g., '0 2 * * 0' for weekly Sunday at 2 AM
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create table for rotation history and audit logs
CREATE TABLE public.rotation_logs (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  credential_id UUID REFERENCES public.credentials(id) ON DELETE CASCADE NOT NULL,
  rotation_trigger TEXT NOT NULL, -- 'scheduled', 'manual', 'emergency'
  status rotation_status NOT NULL,
  started_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  completed_at TIMESTAMP WITH TIME ZONE,
  error_message TEXT,
  old_secret_hash TEXT, -- Hash of old secret for audit purposes
  new_secret_hash TEXT, -- Hash of new secret for audit purposes
  performed_by UUID REFERENCES auth.users(id),
  metadata JSONB DEFAULT '{}'
);

-- Create table for external secret managers configuration
CREATE TABLE public.secret_managers (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL, -- 'aws_secrets_manager', 'hashicorp_vault', 'azure_key_vault'
  endpoint_url TEXT,
  region TEXT,
  configuration JSONB NOT NULL DEFAULT '{}',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Enable Row Level Security
ALTER TABLE public.credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rotation_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rotation_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.secret_managers ENABLE ROW LEVEL SECURITY;

-- Create policies for admin access (you'll need to implement authentication first)
CREATE POLICY "Admin can manage credentials" 
  ON public.credentials 
  FOR ALL 
  USING (true);

CREATE POLICY "Admin can manage rotation schedules" 
  ON public.rotation_schedules 
  FOR ALL 
  USING (true);

CREATE POLICY "Admin can view rotation logs" 
  ON public.rotation_logs 
  FOR SELECT 
  USING (true);

CREATE POLICY "Admin can manage secret managers" 
  ON public.secret_managers 
  FOR ALL 
  USING (true);

-- Create function to automatically calculate next rotation date
CREATE OR REPLACE FUNCTION calculate_next_rotation_date(
  last_rotated TIMESTAMP WITH TIME ZONE,
  interval_days INTEGER
) RETURNS TIMESTAMP WITH TIME ZONE AS $$
BEGIN
  IF last_rotated IS NULL THEN
    RETURN NOW() + (interval_days || ' days')::INTERVAL;
  ELSE
    RETURN last_rotated + (interval_days || ' days')::INTERVAL;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update next_rotation_at
CREATE OR REPLACE FUNCTION update_next_rotation_trigger()
RETURNS TRIGGER AS $$
BEGIN
  NEW.next_rotation_at := calculate_next_rotation_date(
    NEW.last_rotated_at, 
    NEW.rotation_interval_days
  );
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER credentials_update_next_rotation
  BEFORE INSERT OR UPDATE ON public.credentials
  FOR EACH ROW
  EXECUTE FUNCTION update_next_rotation_trigger();

-- Insert some example credential configurations
INSERT INTO public.credentials (name, type, description, external_secret_path, rotation_interval_days) VALUES
('artifactory-access-token', 'artifactory_token', 'Main Artifactory access token', 'secrets/artifactory/access-token', 7),
('ci-cd-service-password', 'service_user_password', 'CI/CD service user password', 'secrets/artifactory/ci-cd-password', 30),
('ldap-manager-password', 'ldap_password', 'LDAP manager service password', 'secrets/ldap/manager-password', 30),
('ssl-client-cert', 'ssl_certificate', 'Client SSL certificate for mTLS', 'secrets/ssl/client-cert', 90);

-- Insert example rotation schedules
INSERT INTO public.rotation_schedules (credential_id, cron_expression) 
SELECT id, '0 2 * * 0' FROM public.credentials WHERE name = 'artifactory-access-token';

INSERT INTO public.rotation_schedules (credential_id, cron_expression) 
SELECT id, '0 3 1 * *' FROM public.credentials WHERE name = 'ci-cd-service-password';

-- Insert example secret manager configurations
INSERT INTO public.secret_managers (name, type, endpoint_url, region, configuration) VALUES
('aws-secrets-manager', 'aws_secrets_manager', 'https://secretsmanager.us-east-1.amazonaws.com', 'us-east-1', '{"role_arn": "arn:aws:iam::123456789012:role/SecretsManagerRole"}'),
('hashicorp-vault', 'hashicorp_vault', 'https://vault.company.com', null, '{"auth_method": "kubernetes", "mount_path": "secret"}'),
('azure-key-vault', 'azure_key_vault', 'https://company-vault.vault.azure.net/', null, '{"tenant_id": "12345678-1234-1234-1234-123456789012"}');
