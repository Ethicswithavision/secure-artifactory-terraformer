
import React from 'react';
import { CredentialDashboard } from '@/components/CredentialDashboard';
import { TerraformCloudSettings } from '@/components/TerraformCloudSettings';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';

const CredentialsPage: React.FC = () => {
  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto py-8">
        <h1 className="text-3xl font-bold mb-8">Credential Management</h1>
        
        <Tabs defaultValue="dashboard" className="space-y-6">
          <TabsList>
            <TabsTrigger value="dashboard">Dashboard</TabsTrigger>
            <TabsTrigger value="terraform">Terraform Cloud</TabsTrigger>
          </TabsList>
          
          <TabsContent value="dashboard">
            <CredentialDashboard />
          </TabsContent>
          
          <TabsContent value="terraform">
            <TerraformCloudSettings />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  );
};

export default CredentialsPage;
