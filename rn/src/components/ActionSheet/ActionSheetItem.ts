export type ActionSheetItem = {
  title: string;
  role: 'default' | 'destructive' | 'cancel';
  // 시트가 닫힌 뒤에 실행된다.
  handler?: () => void;
};
