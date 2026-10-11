import { useEffect } from 'react';
import type { Dispatch } from 'react';
import { subscribeSearchVisibility } from 'plyst-bridge';
import type { HomeAction } from './homeState';
import { useClips } from './useClips';

export function useHomeClips(dispatch: Dispatch<HomeAction>) {
  useClips(dispatch);
  useEffect(() => {
    const subscription = subscribeSearchVisibility((isVisible) => {
      dispatch({ type: 'searchVisibilityChanged', isVisible });
    });
    return () => subscription.remove();
  }, [dispatch]);
}
