export type ClipTextRange = { location: number; length: number };

export type ClipCardProps = {
  name: string | null;
  metadata: string;
  nameHighlights?: ClipTextRange[];
  onCopyButtonPress?: () => void;
  onCopyButtonLongPress?: () => void;
};
