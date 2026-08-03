export interface RecipeDraft {
  name: string;
  steps: string[];
  ingredients: string[];
  seasonings: string[];
  experience: string[];
  photoPath: string;
  originalText: string;
}

export interface RecipeRecord {
  id: string;
  name: string;
  steps: string[];
  ingredients: string[];
  seasonings: string[];
  experience: string[];
  photoPath: string;
  originalText: string;
  createdAt: number;
  updatedAt: number;
}

export interface DraftSession {
  originalText: string;
  recipeName: string;
  steps: string[];
  ingredients: string[];
  seasonings: string[];
  experience: string[];
  lastInstruction: string;
  updatedAt: number;
}
