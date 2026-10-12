import { createAction } from '../../Shared/State/screenStore';

export const textDetailActions = {
  viewDidLoad: createAction('action/viewDidLoad'),
  save: createAction('action/save'),
  copy: createAction('action/copy'),
  delete: createAction('action/delete'),
};
