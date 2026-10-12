import { createAction } from '../../Shared/State/screenStore';

export const imageDetailActions = {
  viewDidLoad: createAction('action/viewDidLoad'),
  save: createAction('action/save'),
  copy: createAction('action/copy'),
  delete: createAction('action/delete'),
  previewRequested: createAction('action/previewRequested'),
  saveToPhotos: createAction('action/saveToPhotos'),
};
