"use client";

import { useEffect } from "react";

import { apiFetch } from "@/lib/client-api";

export function NotificationsSeenMarker() {
  useEffect(() => {
    void apiFetch("/activity/notifications-seen", {
      method: "POST"
    }).catch(() => undefined);
  }, []);

  return null;
}
