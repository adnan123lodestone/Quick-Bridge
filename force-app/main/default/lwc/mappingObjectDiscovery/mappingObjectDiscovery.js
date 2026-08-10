export function normalizeObjectApiName(value) {
  const apiName = String(value || "").trim();
  if (apiName.endsWith("__c") && (apiName.match(/__/g) || []).length > 1) {
    return apiName.substring(apiName.indexOf("__") + 2).toLowerCase();
  }
  return apiName.toLowerCase();
}

export function buildObjectOptions(result, selectedValue) {
  return (result || []).map((item) => ({
    label: item.label,
    value: item.value,
    available: item.available !== false,
    disabled: item.available === false,
    configured: item.configured === true,
    configuredExternalObjects: [...(item.configuredExternalObjects || [])],
    selected: item.value === selectedValue
  }));
}

export function findObjectOption(options, objectApiName) {
  const normalizedName = normalizeObjectApiName(objectApiName);
  return (options || []).find(
    (option) => normalizeObjectApiName(option.value) === normalizedName
  );
}

export function selectConfiguredExternalObject(
  objectOptions,
  objectApiName,
  externalOptions,
  currentExternalObject
) {
  const objectOption = findObjectOption(objectOptions, objectApiName);
  const configured = objectOption?.configuredExternalObjects || [];
  if (configured.includes(currentExternalObject)) {
    return currentExternalObject;
  }
  return (
    (externalOptions || []).find((option) => configured.includes(option.value))
      ?.value || ""
  );
}

export function isConfiguredPair(objectOptions, objectApiName, externalObject) {
  if (!objectApiName || !externalObject) return false;
  const objectOption = findObjectOption(objectOptions, objectApiName);
  return Boolean(
    objectOption?.configuredExternalObjects?.includes(externalObject)
  );
}

export function registerConfiguredPair(
  objectOptions,
  objectApiName,
  externalObject
) {
  if (!objectApiName || !externalObject) return objectOptions || [];
  const normalizedName = normalizeObjectApiName(objectApiName);
  return (objectOptions || []).map((option) => {
    if (normalizeObjectApiName(option.value) !== normalizedName) return option;
    const configuredExternalObjects = [
      ...new Set([...(option.configuredExternalObjects || []), externalObject])
    ];
    return {
      ...option,
      configured: true,
      configuredExternalObjects
    };
  });
}

export function firstAvailableObject(options) {
  return (
    (options || []).find((option) => option.available !== false)?.value || ""
  );
}