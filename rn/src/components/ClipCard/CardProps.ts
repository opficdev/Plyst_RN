export type ClipCardProps = {
  name: string | null;
  metadata: string;
  onCopyButtonPress?: () => void;
  onCopyButtonLongPress?: () => void;
};
