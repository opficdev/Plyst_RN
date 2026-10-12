import { createAction } from '../../Shared/State/screenStore';

export const homeActions = {
  viewDidLoad: createAction('action/viewDidLoad'),
  saveCurrentClipboard: createAction('action/saveCurrentClipboard'),
  setPinned: createAction('action/setPinned'),
  copy: createAction<string>('action/copy'),
  delete: createAction('action/delete'),
};
