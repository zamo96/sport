/** Shared photo limits; safe to import from browser components. */
export const MAX_IMAGE_MEGABYTES = 20;
export const MAX_IMAGE_BYTES = MAX_IMAGE_MEGABYTES * 1024 * 1024;
export const IMAGE_SIZE_ERROR = `Фото должно быть не больше ${MAX_IMAGE_MEGABYTES} МБ`;
export const NORMALIZED_IMAGE_SIZE_ERROR = `Фото после обработки должно быть не больше ${MAX_IMAGE_MEGABYTES} МБ`;
