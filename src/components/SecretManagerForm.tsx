
import React, { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { Textarea } from '@/components/ui/textarea';
import { useToast } from '@/hooks/use-toast';
import { Settings, Trash2 } from 'lucide-react';

interface SecretManager {
  id: string;
  name: string;
  type: string;
  endpoint_url: string | null;
  region: string | null;
  configuration: any;
  is_active: boolean;
}

export const SecretManagerForm: React.FC = () => {
  const [secretManagers, setSecretManagers] = useState<SecretManager[]>([]);
  const [formData, setFormData] = useState({
    name: '',
    type: '',
    endpoint_url: '',
    region: '',
    configuration: '{}',
    is_active: true,
  });
  const [loading, setLoading] = useState(false);
  const { toast } = useToast();

  useEffect(() => {
    fetchSecretManagers();
  }, []);

  const fetchSecretManagers = async () => {
    try {
      const { data, error } = await supabase
        .from('secret_managers')
        .select('*')
        .order('name');

      if (error) throw error;
      setSecretManagers(data || []);
    } catch (error) {
      console.error('Error fetching secret managers:', error);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const configObj = JSON.parse(formData.configuration);
      
      const { error } = await supabase
        .from('secret_managers')
        .insert([{
          ...formData,
          configuration: configObj,
        }]);

      if (error) throw error;

      toast({
        title: 'Success',
        description: 'Secret manager added successfully',
      });

      setFormData({
        name: '',
        type: '',
        endpoint_url: '',
        region: '',
        configuration: '{}',
        is_active: true,
      });

      fetchSecretManagers();
    } catch (error) {
      console.error('Error adding secret manager:', error);
      toast({
        title: 'Error',
        description: 'Failed to add secret manager',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const deleteSecretManager = async (id: string) => {
    try {
      const { error } = await supabase
        .from('secret_managers')
        .delete()
        .eq('id', id);

      if (error) throw error;

      toast({
        title: 'Success',
        description: 'Secret manager deleted successfully',
      });

      fetchSecretManagers();
    } catch (error) {
      console.error('Error deleting secret manager:', error);
      toast({
        title: 'Error',
        description: 'Failed to delete secret manager',
        variant: 'destructive',
      });
    }
  };

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center space-x-2">
            <Settings className="h-5 w-5" />
            <span>Secret Manager Configuration</span>
          </CardTitle>
          <CardDescription>
            Configure external secret management systems for secure credential storage
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-2">
                <Label htmlFor="name">Name</Label>
                <Input
                  id="name"
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  placeholder="e.g., prod-vault"
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="type">Type</Label>
                <Select
                  value={formData.type}
                  onValueChange={(value) => setFormData({ ...formData, type: value })}
                  required
                >
                  <SelectTrigger>
                    <SelectValue placeholder="Select secret manager type" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="aws_secrets_manager">AWS Secrets Manager</SelectItem>
                    <SelectItem value="hashicorp_vault">HashiCorp Vault</SelectItem>
                    <SelectItem value="azure_key_vault">Azure Key Vault</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-2">
                <Label htmlFor="endpoint_url">Endpoint URL</Label>
                <Input
                  id="endpoint_url"
                  value={formData.endpoint_url}
                  onChange={(e) => setFormData({ ...formData, endpoint_url: e.target.value })}
                  placeholder="https://vault.company.com"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="region">Region</Label>
                <Input
                  id="region"
                  value={formData.region}
                  onChange={(e) => setFormData({ ...formData, region: e.target.value })}
                  placeholder="us-east-1"
                />
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="configuration">Configuration (JSON)</Label>
              <Textarea
                id="configuration"
                value={formData.configuration}
                onChange={(e) => setFormData({ ...formData, configuration: e.target.value })}
                placeholder='{"auth_method": "kubernetes", "mount_path": "secret"}'
                rows={4}
              />
            </div>

            <div className="flex items-center space-x-2">
              <Switch
                id="is_active"
                checked={formData.is_active}
                onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
              />
              <Label htmlFor="is_active">Active</Label>
            </div>

            <Button type="submit" disabled={loading}>
              {loading ? 'Adding...' : 'Add Secret Manager'}
            </Button>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Configured Secret Managers</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {secretManagers.map((manager) => (
              <div key={manager.id} className="flex items-center justify-between p-4 border rounded-lg">
                <div>
                  <h4 className="font-medium">{manager.name}</h4>
                  <p className="text-sm text-muted-foreground">{manager.type}</p>
                  <p className="text-xs text-muted-foreground">{manager.endpoint_url}</p>
                </div>
                <div className="flex items-center space-x-2">
                  <span className={`px-2 py-1 text-xs rounded ${manager.is_active ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}`}>
                    {manager.is_active ? 'Active' : 'Inactive'}
                  </span>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => deleteSecretManager(manager.id)}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            ))}
          </div>
        </CardContent>
      </Card>
    </div>
  );
};
