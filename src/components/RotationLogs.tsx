
import React from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Clock, CheckCircle, XCircle, AlertCircle, RefreshCw } from 'lucide-react';
import { format } from 'date-fns';

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

interface RotationLogsProps {
  logs: RotationLog[];
}

export const RotationLogs: React.FC<RotationLogsProps> = ({ logs }) => {
  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed':
        return <CheckCircle className="h-4 w-4 text-green-500" />;
      case 'failed':
        return <XCircle className="h-4 w-4 text-red-500" />;
      case 'in_progress':
        return <RefreshCw className="h-4 w-4 text-blue-500 animate-spin" />;
      case 'pending':
        return <Clock className="h-4 w-4 text-yellow-500" />;
      default:
        return <AlertCircle className="h-4 w-4 text-gray-500" />;
    }
  };

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'completed':
        return <Badge variant="default" className="bg-green-100 text-green-800">Completed</Badge>;
      case 'failed':
        return <Badge variant="destructive">Failed</Badge>;
      case 'in_progress':
        return <Badge variant="secondary">In Progress</Badge>;
      case 'pending':
        return <Badge variant="outline">Pending</Badge>;
      default:
        return <Badge variant="secondary">{status}</Badge>;
    }
  };

  const getTriggerBadge = (trigger: string) => {
    switch (trigger) {
      case 'scheduled':
        return <Badge variant="outline">Scheduled</Badge>;
      case 'manual':
        return <Badge variant="secondary">Manual</Badge>;
      case 'emergency':
        return <Badge variant="destructive">Emergency</Badge>;
      default:
        return <Badge variant="outline">{trigger}</Badge>;
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Rotation Activity Logs</CardTitle>
        <CardDescription>
          Recent credential rotation activities and their outcomes
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ScrollArea className="h-[600px]">
          <div className="space-y-4">
            {logs.map((log) => (
              <div key={log.id} className="flex items-start space-x-4 p-4 border rounded-lg">
                <div className="flex-shrink-0 mt-1">
                  {getStatusIcon(log.status)}
                </div>
                <div className="flex-grow min-w-0">
                  <div className="flex items-center justify-between mb-2">
                    <h4 className="font-medium truncate">{log.credentials?.name}</h4>
                    <div className="flex items-center space-x-2">
                      {getTriggerBadge(log.rotation_trigger)}
                      {getStatusBadge(log.status)}
                    </div>
                  </div>
                  <div className="text-sm text-muted-foreground space-y-1">
                    <p>Started: {format(new Date(log.started_at), 'PPpp')}</p>
                    {log.completed_at && (
                      <p>Completed: {format(new Date(log.completed_at), 'PPpp')}</p>
                    )}
                    {log.error_message && (
                      <p className="text-red-600 bg-red-50 p-2 rounded text-xs">
                        Error: {log.error_message}
                      </p>
                    )}
                  </div>
                </div>
              </div>
            ))}
            {logs.length === 0 && (
              <div className="text-center py-8 text-muted-foreground">
                <Clock className="h-12 w-12 mx-auto mb-4 opacity-50" />
                <p>No rotation logs available yet</p>
              </div>
            )}
          </div>
        </ScrollArea>
      </CardContent>
    </Card>
  );
};
