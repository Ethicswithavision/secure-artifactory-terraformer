
interface TFCVariableSet {
  id: string;
  type: string;
  attributes: {
    name: string;
    description: string;
    global: boolean;
  };
}

interface TFCVariable {
  id: string;
  type: string;
  attributes: {
    key: string;
    value: string;
    category: 'terraform' | 'env';
    sensitive: boolean;
    description: string;
  };
}

interface TFCWorkspace {
  id: string;
  type: string;
  attributes: {
    name: string;
    'execution-mode': string;
    'auto-apply': boolean;
  };
}

export class TerraformCloudService {
  private baseUrl = 'https://app.terraform.io/api/v2';
  private token: string;
  private organization: string;

  constructor(token: string, organization: string) {
    this.token = token;
    this.organization = organization;
  }

  private async request(endpoint: string, options: RequestInit = {}) {
    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      ...options,
      headers: {
        'Authorization': `Bearer ${this.token}`,
        'Content-Type': 'application/vnd.api+json',
        ...options.headers,
      },
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`TFC API Error: ${response.status} - ${errorText}`);
    }

    return response.json();
  }

  async getVariableSet(variableSetName: string): Promise<TFCVariableSet | null> {
    try {
      const response = await this.request(`/organizations/${this.organization}/varsets`);
      const variableSet = response.data.find((vs: TFCVariableSet) => 
        vs.attributes.name === variableSetName
      );
      return variableSet || null;
    } catch (error) {
      console.error('Error fetching variable set:', error);
      return null;
    }
  }

  async createVariableSet(name: string, description: string, global: boolean = true): Promise<TFCVariableSet> {
    const payload = {
      data: {
        type: 'varsets',
        attributes: {
          name,
          description,
          global
        }
      }
    };

    const response = await this.request(`/organizations/${this.organization}/varsets`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    return response.data;
  }

  async updateVariableInSet(variableSetId: string, key: string, value: string, sensitive: boolean = true): Promise<void> {
    // First, try to find existing variable
    const existingVars = await this.getVariableSetVariables(variableSetId);
    const existingVar = existingVars.find(v => v.attributes.key === key);

    if (existingVar) {
      // Update existing variable
      const payload = {
        data: {
          type: 'vars',
          id: existingVar.id,
          attributes: {
            key,
            value,
            sensitive,
            category: 'terraform' as const
          }
        }
      };

      await this.request(`/varsets/${variableSetId}/relationships/vars/${existingVar.id}`, {
        method: 'PATCH',
        body: JSON.stringify(payload),
      });
    } else {
      // Create new variable
      const payload = {
        data: {
          type: 'vars',
          attributes: {
            key,
            value,
            sensitive,
            category: 'terraform' as const,
            description: `Rotated credential: ${key}`
          }
        }
      };

      await this.request(`/varsets/${variableSetId}/relationships/vars`, {
        method: 'POST',
        body: JSON.stringify(payload),
      });
    }
  }

  async getVariableSetVariables(variableSetId: string): Promise<TFCVariable[]> {
    const response = await this.request(`/varsets/${variableSetId}/relationships/vars`);
    return response.data;
  }

  async triggerWorkspaceRun(workspaceName: string, message: string = 'Automated credential rotation'): Promise<string> {
    // Get workspace ID
    const workspace = await this.getWorkspace(workspaceName);
    if (!workspace) {
      throw new Error(`Workspace ${workspaceName} not found`);
    }

    const payload = {
      data: {
        type: 'runs',
        attributes: {
          message,
          'is-destroy': false,
          'auto-apply': false
        },
        relationships: {
          workspace: {
            data: {
              type: 'workspaces',
              id: workspace.id
            }
          }
        }
      }
    };

    const response = await this.request('/runs', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    return response.data.id;
  }

  async getWorkspace(workspaceName: string): Promise<TFCWorkspace | null> {
    try {
      const response = await this.request(`/organizations/${this.organization}/workspaces/${workspaceName}`);
      return response.data;
    } catch (error) {
      console.error('Error fetching workspace:', error);
      return null;
    }
  }

  async listWorkspaces(): Promise<TFCWorkspace[]> {
    const response = await this.request(`/organizations/${this.organization}/workspaces`);
    return response.data;
  }
}
