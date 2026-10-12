import { createAction } from '../../Shared/State/screenStore';

export const searchActions = {
  viewDidLoad: createAction('action/viewDidLoad'),
  submitQuery: createAction('action/submitQuery'),
  removeRecentTerm: createAction<string>('action/removeRecentTerm'),
  clearRecentTerms: createAction('action/clearRecentTerms'),
  copy: createAction<string>('action/copy'),
};
