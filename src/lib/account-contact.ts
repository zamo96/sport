/**
 * Контакт аккаунта для админки, жалоб и журналов аудита. Email есть не у всех:
 * аккаунты, созданные входом по телефону или через VK ID, живут по номеру.
 */
export function accountContact(user: { email?: string | null; phone?: string | null }) {
  return user.email ?? user.phone ?? "без контакта";
}
