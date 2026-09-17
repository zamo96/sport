/** One notification, as every transport and the realtime channel see it. */
export type PushPayload = {
  userId: string;
  title: string;
  body: string;
  href: string;
  sound?: boolean;
  deliveryId?: string;
};
