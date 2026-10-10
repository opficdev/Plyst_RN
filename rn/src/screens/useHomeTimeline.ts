import { useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { nextHomeTimelineChange } from './homeTimeline';

export function useHomeTimeline(
  createdAtList: readonly number[],
  isEnabled: boolean,
): number {
  const [now, setNow] = useState(Date.now);
  const dates = useRef(createdAtList);
  const reschedule = useRef<(() => void) | null>(null);

  useEffect(() => {
    dates.current = createdAtList;
    reschedule.current?.();
  }, [createdAtList]);

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    function stop() {
      if (timer !== undefined) clearTimeout(timer);
      timer = undefined;
    }
    function schedule() {
      stop();
      if (!isEnabled || AppState.currentState !== 'active') return;
      const current = Date.now();
      const next = nextHomeTimelineChange(dates.current, current);
      if (next !== null)
        timer = setTimeout(refresh, Math.max(0, next - current));
    }
    function refresh() {
      if (!isEnabled || AppState.currentState !== 'active') return;
      stop();
      setNow(Date.now());
      schedule();
    }
    reschedule.current = schedule;
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') refresh();
      else stop();
    });
    refresh();
    return () => {
      stop();
      reschedule.current = null;
      subscription.remove();
    };
  }, [isEnabled]);

  return now;
}
