
import React, { useState, useEffect } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Switch } from '@/components/ui/switch';
import { useToast } from '@/hooks/use-toast';
import { Settings, Cloud, Zap } from 'lucide-react';
import { Alert, AlertDescription } from '@/components/ui/alert';

interface TFCConfig {
  apiToken: string;
  organization: string;
  variableSetId: string;
  workspaces: string[];
  autoTriggerRuns: boolean;
}

export const TerraformCloudSettings: React.FC = () => {
  const [config, setConfig] = useState<TFCConfig>({
    apiToken: '',
    organization: '',
    variableSetId: '',
    workspaces: [],
    autoTriggerRuns: false,
  });
  const [workspaceInput, setWorkspaceInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [testingConnection, setTestingConnection] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    // Load existing config from localStorage
    const savedConfig = localStorage.getItem('tfc-config');
    if (savedConfig) {
      setConfig(JSON.parse(savedConfig));
    }
  }, []);

  const saveConfig = () => {
    setLoading(true);
    try {
      localStorage.setItem('tfc-config', JSON.stringify(config));
      toast({
        title: 'Configuration Saved',
        description: 'Terraform Cloud settings have been saved.',
      });
    } catch (error) {
      toast({
        title: 'Error',
        description: 'Failed to save configuration.',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const testConnection = async () => {
    if (!config.apiToken || !config.organization) {
      toast({
        title: 'Missing Configuration',
        description: 'Please provide API token and organization.',
        variant: 'destructive',
      });
      return;
    }

    setTestingConnection(true);
    try {
      const response = await fetch(`https://app.terraform.io/api/v2/organizations/${config.organization}`, {
        headers: {
          'Authorization': `Bearer ${config.apiToken}`,
          'Content-Type': 'application/vnd.api+json',
        },
      });

      if (response.ok) {
        toast({
          title: 'Connection Successful',
          description: 'Successfully connected to Terraform Cloud.',
        });
      } else {
        throw new Error(`HTTP ${response.status}`);
      }
    } catch (error) {
      toast({
        title: 'Connection Failed',
        description: 'Failed to connect to Terraform Cloud. Check your credentials.',
        variant: 'destructive',
      });
    } finally {
      setTestingConnection(false);
    }
  };

  const addWorkspace = () => {
    if (workspaceInput && !config.workspaces.includes(workspaceInput)) {
      setConfig({
        ...config,
        workspaces: [...config.workspaces, workspaceInput]
      });
      setWorkspaceInput('');
    }
  };

  const removeWorkspace = (workspace: string) => {
    setConfig({
      ...config,
      workspaces: config.workspaces.filter(w => w !== workspace)
    });
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <Cloud className="h-5 w-5" />
          <span>Terraform Cloud Integration</span>
        </CardTitle>
        <CardDescription>
          Configure Terraform Cloud API integration for automatic credential rotation
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        <Alert>
          <Settings className="h-4 w-4" />
          <AlertDescription>
            This integration allows automatic updating of TFC Variable Sets when credentials are rotated.
            Credentials will be stored in a global Variable Set and applied to specified workspaces.
          </AlertDescription>
        </Alert>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div className="space-y-2">
            <Label htmlFor="apiToken">API Token</Label>
            <Input
              id="apiToken"
              type="password"
              value={config.apiToken}
              onChange={(e) => setConfig({ ...config, apiToken: e.target.value })}
              placeholder="Enter your TFC API token"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="organization">Organization</Label>
            <Input
              id="organization"
              value={config.organization}
              onChange={(e) => setConfig({ ...config, organization: e.target.value })}
              placeholder="Your TFC organization name"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="variableSetId">Variable Set ID</Label>
            <Input
              id="variableSetId"
              value={config.variableSetId}
              onChange={(e) => setConfig({ ...config, variableSetId: e.target.value })}
              placeholder="Variable Set ID for credentials"
            />
          </div>

          <div className="flex items-center space-x-2">
            <Switch
              id="autoTrigger"
              checked={config.autoTriggerRuns}
              onCheckedChange={(checked) => setConfig({ ...config, autoTriggerRuns: checked })}
            />
            <Label htmlFor="autoTrigger">Auto-trigger workspace runs</Label>
          </div>
        </div>

        <div className="space-y-4">
          <Label>Workspaces to Update</Label>
          <div className="flex space-x-2">
            <Input
              value={workspaceInput}
              onChange={(e) => setWorkspaceInput(e.target.value)}
              placeholder="Workspace name"
              onKeyPress={(e) => e.key === 'Enter' && addWorkspace()}
            />
            <Button onClick={addWorkspace} type="button">Add</Button>
          </div>
          
          {config.workspaces.length > 0 && (
            <div className="space-y-2">
              <Label>Configured Workspaces:</Label>
              <div className="flex flex-wrap gap-2">
                {config.workspaces.map((workspace) => (
                  <div
                    key={workspace}
                    className="flex items-center space-x-2 bg-secondary px-3 py-1 rounded-md"
                  >
                    <span className="text-sm">{workspace}</span>
                    <button
                      onClick={() => removeWorkspace(workspace)}
                      className="text-red-500 hover:text-red-700"
                    >
                      ×
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        <div className="flex space-x-4">
          <Button onClick={testConnection} disabled={testingConnection} variant="outline">
            {testingConnection ? 'Testing...' : 'Test Connection'}
          </Button>
          <Button onClick={saveConfig} disabled={loading}>
            {loading ? 'Saving...' : 'Save Configuration'}
          </Button>
        </div>

        <Alert>
          <Zap className="h-4 w-4" />
          <AlertDescription>
            <strong>How it works:</strong> When credentials are rotated, the system will automatically update
            the specified Variable Set in Terraform Cloud with new credential values. If auto-trigger is enabled,
            it will also trigger runs on the configured workspaces.
          </AlertDescription>
        </Alert>
      </CardContent>
    </Card>
  );
};
