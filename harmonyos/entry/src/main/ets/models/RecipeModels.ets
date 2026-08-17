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

export interface DraftRecipeVersion {
  recipeName: string;
  steps: string[];
  ingredients: string[];
  seasonings: string[];
  experience: string[];
  instruction: string;
  assistantReply: string;
}

export interface DraftSession {
  originalText: string;
  questionText: string;
  questionIds: string[];
  recipeName: string;
  steps: string[];
  ingredients: string[];
  seasonings: string[];
  experience: string[];
  lastInstruction: string;
  assistantReply: string;
  history: DraftRecipeVersion[];
  updatedAt: number;
}
