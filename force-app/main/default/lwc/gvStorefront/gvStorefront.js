export function customerMessage(error, fallback) {
  const message = error?.body?.message || error?.message;
  if (/stock|quantity is unavailable/i.test(message || ""))
    return "The requested quantity is unavailable. Please choose fewer pieces.";
  return message && !/Class\.|SELECT |Exception|GV[A-Z]/.test(message)
    ? message
    : fallback;
}
