import type { CodegenTypes, TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type ToastRequest = {
  message: string;
  isSuccess: boolean;
};

export interface Spec extends TurboModule {
  readonly onToastRequest: CodegenTypes.EventEmitter<ToastRequest>;
  ready(): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('PlystToast');
