
import React, { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { AlertTriangle, Shield, Clock, RefreshCw, Key, Database } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { CredentialForm } from './CredentialForm';
import { RotationLogs } from './RotationLogs';
import { SecretManagerForm } from './SecretManagerForm';

interface Credential {
  id: string;
  name: string;
  type: string;
  description: string;
  rotation_interval_days: number;
  expires_at: string | null;
  last_rotated_at: string | null;
  next_rotation_at: string | null;
  is_active: boolean;
}

interface RotationLog {
  id: string;
  credential_id: string;
  rotation_trigger: string;
  status: string;
  started_at: string;
  completed_at: string | null;
  error_message: string | null;
  credentials: { name: string };
}

export const CredentialDashboard: React.FC = () => {
  const [credentials, setCredentials] = useState<Credential[]>([]);
  const [rotationLogs, setRotationLogs] = useState<RotationLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');
  const { toast } = useToast();

  useEffect(() => {
    fetchCredentials();
    fetchRotationLogs();
  }, []);

  const fetchCredentials = async () => {
    try {
      const { data, error } = await supabase
        .from('credentials')
        .select('*')
        .order('next_rotation_at', { ascending: true });

      if (error) throw error;
      setCredentials(data || []);
    } catch (error) {
      console.error('Error fetching credentials:', error);
      toast({
        title: 'Error',
        description: 'Failed to fetch credentials',
        variant: 'destructive',
      });
    } finally {
      setLoading(false);
    }
  };

  const fetchRotationLogs = async () => {
    try {
      const { data, error } = await supabase
        .from('rotation_logs')
        .select(`
          *,
          credentials(name)
        `)
        .order('started_at', { ascending: false })
        .limit(10);

      if (error) throw error;
      setRotationLogs(data || []);
    } catch (error) {
      console.error('Error fetching rotation logs:', error);
    }
  };

  const triggerRotation = async (credentialId: string) => {
    try {
      const { error } = await supabase.functions.invoke('rotate-credential', {
        body: { 
          credentialId,
          trigger: 'manual'
        }
      });

      if (error) throw error;

      toast({
        title: 'Success',
        description: 'Credential rotation initiated',
      });

      fetchCredentials();
      fetchRotationLogs();
    } catch (error) {
      console.error('Error triggering rotation:', error);
      toast({
        title: 'Error',
        description: 'Failed to trigger rotation',
        variant: 'destructive',
      });
    }
  };

  const getStatusBadge = (credential: Credential) => {
    const now = new Date();
    const nextRotation = credential.next_rotation_at ? new Date(credential.next_rotation_at) : null;
    const daysDiff = nextRotation ? Math.ceil((nextRotation.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)) : null;

    if (!credential.is_active) {
      return <Badge variant="secondary">Inactive</Badge>;
    }

    if (daysDiff !== null) {
      if (daysDiff <= 0) {
        return <Badge variant="destructive">Overdue</Badge>;
      } else if (daysDiff <= 7) {
        return <Badge variant="outline">Due Soon</Badge>;
      }
    }

    return <Badge variant="default">Active</Badge>;
  };

  const getCredentialIcon = (type: string) => {
    switch (type) {
      case 'artifactory_token':
        return <Database className="h-4 w-4" />;
      case 'ssl_certificate':
        return <Shield className="h-4 w-4" />;
      default:
        return <Key className="h-4 w-4" />;
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw className="h-8 w-8 animate-spin" />
      </div>
    );
  }

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Credential Management</h1>
          <p className="text-muted-foreground">
            Manage and rotate credentials automatically for enhanced security
          </p>
        </div>
      </div>

      <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
        <TabsList className="grid w-full grid-cols-4">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="credentials">Credentials</TabsTrigger>
          <TabsTrigger value="logs">Rotation Logs</TabsTrigger>
          <TabsTrigger value="settings">Settings</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Total Credentials</CardTitle>
                <Key className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">{credentials.length}</div>
                <p className="text-xs text-muted-foreground">
                  {credentials.filter(c => c.is_active).length} active
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Due for Rotation</CardTitle>
                <Clock className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">
                  {credentials.filter(c => {
                    const nextRotation = c.next_rotation_at ? new Date(c.next_rotation_at) : null;
                    return nextRotation && nextRotation <= new Date();
                  }).length}
                </div>
                <p className="text-xs text-muted-foreground">
                  Requires immediate attention
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium">Recent Rotations</CardTitle>
                <RefreshCw className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold">
                  {rotationLogs.filter(log => log.status === 'completed').length}
                </div>
                <p className="text-xs text-muted-foreground">
                  Successful this month
                </p>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <CardTitle>Credentials Requiring Attention</CardTitle>
              <CardDescription>
                Credentials that are overdue or due soon for rotation
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="space-y-4">
                {credentials
                  .filter(credential => {
                    const nextRotation = credential.next_rotation_at ? new Date(credential.next_rotation_at) : null;
                    const daysDiff = nextRotation ? Math.ceil((nextRotation.getTime() - new Date().getTime()) / (1000 * 60 * 60 * 24)) : null;
                    return daysDiff !== null && daysDiff <= 7;
                  })
                  .map(credential => (
                    <div key={credential.id} className="flex items-center justify-between p-4 border rounded-lg">
                      <div className="flex items-center space-x-3">
                        {getCredentialIcon(credential.type)}
                        <div>
                          <p className="font-medium">{credential.name}</p>
                          <p className="text-sm text-muted-foreground">{credential.description}</p>
                        </div>
                      </div>
                      <div className="flex items-center space-x-3">
                        {getStatusBadge(credential)}
                        <Button
                          size="sm"
                          onClick={() => triggerRotation(credential.id)}
                          className="flex items-center space-x-1"
                        >
                          <RefreshCw className="h-3 w-3" />
                          <span>Rotate Now</span>
                        </Button>
                      </div>
                    </div>
                  ))}
                {credentials.filter(credential => {
                  const nextRotation = credential.next_rotation_at ? new Date(credential.next_rotation_at) : null;
                  const daysDiff = nextRotation ? Math.ceil((nextRotation.getTime() - new Date().getTime()) / (1000 * 60 * 60 * 24)) : null;
                  return daysDiff !== null && daysDiff <= 7;
                }).length === 0 && (
                  <div className="text-center py-8 text-muted-foreground">
                    <Shield className="h-12 w-12 mx-auto mb-4 opacity-50" />
                    <p>All credentials are up to date!</p>
                  </div>
                )}
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="credentials">
          <CredentialForm onCredentialAdded={fetchCredentials} />
        </TabsContent>

        <TabsContent value="logs">
          <RotationLogs logs={rotationLogs} />
        </TabsContent>

        <TabsContent value="settings">
          <SecretManagerForm />
        </TabsContent>
      </Tabs>
    </div>
  );
};
