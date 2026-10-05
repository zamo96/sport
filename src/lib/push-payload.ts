/** One notification, as every transport and the realtime channel see it. */
export type PushPayload = {
  userId: string;
  title: string;
  body: string;
  /**
   * Text for the in-app banner only. It travels over our own realtime channel,
   * while `body` goes through Apple and Google, so private content belongs here.
   */
  inAppBody?: string;
  href: string;
  sound?: boolean;
  deliveryId?: string;
};
