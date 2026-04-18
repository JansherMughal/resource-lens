/**
 * Placeholder Settings resolver for AppSync direct Lambda integration.
 * Replace with real DynamoDB logic using SETTINGS_TABLE_NAME.
 */
exports.handler = async (event) => {
  const table = process.env.SETTINGS_TABLE_NAME;
  return {
    settingId: event.arguments?.settingId || "unknown",
    value: JSON.stringify({ table, event }),
  };
};
