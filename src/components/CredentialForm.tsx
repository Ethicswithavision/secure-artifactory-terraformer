
import React, { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Switch } from '@/components/ui/switch';
import { useToast } from '@/hooks/use-toast';
import { Plus } from 'lucide-react';

interface CredentialFormProps {
  onCredentialAdded: () => void;
}

type CredentialType = 'artifactory_token' | 'service_user_password' | 'ldap_password' | 'ssl_certificate';

export const CredentialForm: React.FC<CredentialFormProps> = ({ onCredentialAdded }) => {
  const [formData, setFormData] = useState({
    name: '',
    type: '' as CredentialType,
    description: '',
    external_secret_path: '',
    rotation_interval_days: 30,
    is_active: true,
  });
  const [loading, setLoading] = useState(false);
  const { toast } = useToast();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const { error } = await supabase
        .from('credentials')
        .insert([formData]);

      if (error) throw error;

      toast({
        title: 'Success',
        description: 'Credential added successfully',
      });

      setFormData({
        name: '',
        type: '' as CredentialType,
        description: '',
        external_secret_path: '',
        rotation_interval_days: 30,
        is_active: true,
      });

      onCredentialAdded();
    } catch (error) {
      console.error('Error adding credential:', error);
      toast({
        title: 'Error',
        description: 'Failed to add credential',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center space-x-2">
          <Plus className="h-5 w-5" />
          <span>Add New Credential</span>
        </CardTitle>
        <CardDescription>
          Register a new credential for automated rotation management
        </CardDescription>
      </CardHeader>
      <CardContent>
        <form onSubmit={handleSubmit} className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-2">
              <Label htmlFor="name">Credential Name</Label>
              <Input
                id="name"
                value={formData.name}
                onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                placeholder="e.g., artifactory-prod-token"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="type">Credential Type</Label>
              <Select
                value={formData.type}
                onValueChange={(value: CredentialType) => setFormData({ ...formData, type: value })}
                required
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select credential type" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="artifactory_token">Artifactory Token</SelectItem>
                  <SelectItem value="service_user_password">Service User Password</SelectItem>
                  <SelectItem value="ldap_password">LDAP Password</SelectItem>
                  <SelectItem value="ssl_certificate">SSL Certificate</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <Label htmlFor="external_secret_path">Secret Manager Path</Label>
              <Input
                id="external_secret_path"
                value={formData.external_secret_path}
                onChange={(e) => setFormData({ ...formData, external_secret_path: e.target.value })}
                placeholder="e.g., secrets/artifactory/prod-token"
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="rotation_interval">Rotation Interval (Days)</Label>
              <Input
                id="rotation_interval"
                type="number"
                min="1"
                max="365"
                value={formData.rotation_interval_days}
                onChange={(e) => setFormData({ ...formData, rotation_interval_days: parseInt(e.target.value) })}
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="description">Description</Label>
            <Textarea
              id="description"
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              placeholder="Brief description of this credential's purpose"
              rows={3}
            />
          </div>

          <div className="flex items-center space-x-2">
            <Switch
              id="is_active"
              checked={formData.is_active}
              onCheckedChange={(checked) => setFormData({ ...formData, is_active: checked })}
            />
            <Label htmlFor="is_active">Active (Enable automatic rotation)</Label>
          </div>

          <Button type="submit" disabled={loading} className="w-full">
            {loading ? 'Adding...' : 'Add Credential'}
          </Button>
        </form>
      </CardContent>
    </Card>
  );
};
