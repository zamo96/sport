"use client";

import { useEffect } from "react";

let lockCount = 0;
let previousStyles: {
  bodyOverflow: string;
  htmlOverflow: string;
  bodyPaddingRight: string;
} | null = null;

export function useLockBodyScroll(locked: boolean) {
  useEffect(() => {
    if (!locked) {
      return;
    }

    lockCount += 1;

    if (lockCount === 1) {
      previousStyles = {
        bodyOverflow: document.body.style.overflow,
        htmlOverflow: document.documentElement.style.overflow,
        bodyPaddingRight: document.body.style.paddingRight
      };

      const scrollbarGap = window.innerWidth - document.documentElement.clientWidth;
      if (scrollbarGap > 0) {
        document.body.style.paddingRight = `${scrollbarGap}px`;
      }

      document.body.style.overflow = "hidden";
      document.documentElement.style.overflow = "hidden";
    }

    return () => {
      lockCount = Math.max(0, lockCount - 1);
      if (lockCount > 0) {
        return;
      }

      if (previousStyles) {
        document.body.style.overflow = previousStyles.bodyOverflow;
        document.documentElement.style.overflow = previousStyles.htmlOverflow;
        document.body.style.paddingRight = previousStyles.bodyPaddingRight;
        previousStyles = null;
      }
    };
  }, [locked]);
}
