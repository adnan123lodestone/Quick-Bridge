import { LightningElement } from "lwc";
import getPaymentMetadataConfigs from "@salesforce/apex/PaymentMetadataService.getPaymentMetadataConfigs";
import updatePaymentMetadata from "@salesforce/apex/PaymentMetadataService.updatePaymentMetadata";
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PaymentConfiguration extends LightningElement {
  selectedProvider = "authorizenet";
  paymentMetadataConfigs = [];
  isMetadataSaving = false;
  metadataFormValues = {};

  connectedCallback() {
    this.loadPaymentMetadata();
  }

  get authorizeNetTileClass() {
    return this.getProviderTileClass("authorizenet");
  }

  get stripeTileClass() {
    return this.getProviderTileClass("stripe");
  }

  get paypalTileClass() {
    return this.getProviderTileClass("paypal");
  }

  get selectedProviderLabel() {
    if (this.selectedProvider === "stripe") return "Stripe Selected";
    if (this.selectedProvider === "paypal") return "PayPal Selected";
    return "Authorize.Net Selected";
  }

  getProviderTileClass(providerName) {
    const classes = ["provider-tile"];
    if (this.selectedProvider === providerName) {
      classes.push("provider-tile-selected");
    }
    return classes.join(" ");
  }

  handleProviderSelection(event) {
    const selected = this.getProviderFromEvent(event);
    if (!selected) return;

    this.selectedProvider = selected;

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(config => {
      const isMatch = config.provider.toLowerCase() === selected.toLowerCase();
      return {
        ...config,
        isSelected: isMatch,
        isEditing: isMatch ? config.isEditing : false
      };
    });
  }

  async loadPaymentMetadata() {
    try {
      const configs = await getPaymentMetadataConfigs();
      const fieldLabels = {
        'APILoginId__c': 'API Login ID',
        'PublicClientKey__c': 'Public Client Key',
        'WebhookSigningKey__c': 'Webhook Signing Key',
        'PublishableKey__c': 'Publishable Key',
        'ClientId__c': 'Client ID',
        'Active__c': 'Active',
        'UseSandbox__c': 'Use Sandbox',
        'StartDate__c': 'Start Date',
        'EndDate__c': 'End Date'
      };
      const checkboxFields = new Set(['Active__c', 'UseSandbox__c']);

      this.paymentMetadataConfigs = (configs || []).map(config => {
        const formValues = { ...config.fields };
        return {
          ...config,
          isSelected: config.provider.toLowerCase() === this.selectedProvider.toLowerCase(),
          isEditing: false,
          formValues,
          editableFieldsData: (config.editableFields || []).map(fieldName => ({
            name: fieldName,
            label: fieldLabels[fieldName] || fieldName,
            value: config.fields[fieldName] || '',
            isCheckbox: checkboxFields.has(fieldName),
            displayValue: this.getFieldDisplayValue(fieldName, config.fields[fieldName]),
            currentValue: formValues[fieldName]
          }))
        };
      });

      this.metadataFormValues = {};
      this.paymentMetadataConfigs.forEach((config) => {
        if (!config.formValues) {
          config.formValues = { ...config.fields };
        }
        this.metadataFormValues[config.provider] = config.formValues;
      });

    } catch (error) {
      console.error(error);
    }
  }

  getFieldDisplayValue(fieldName, value) {
    if (fieldName === 'Active__c' || fieldName === 'UseSandbox__c') {
      return value === true || value === 'true' ? 'Yes' : 'No';
    }
    return value || '-';
  }

  getProviderFromEvent(event) {
    let el = event?.currentTarget || event?.target;
    while (el && !(el.dataset && el.dataset.provider)) {
      el = el.parentElement;
    }
    return el?.dataset?.provider || null;
  }

  toggleMetadataEditMode(event) {
    const provider = this.getProviderFromEvent(event);
    if (!provider) return;

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
      if (c.provider === provider) {
        c.isEditing = !c.isEditing;
        if (!c.isEditing) {
          this.metadataFormValues[provider] = { ...c.fields };
        }
      }
      return c;
    });
  }

  handleAddMetadataProvider(event) {
    const provider = this.getProviderFromEvent(event);
    if (!provider) return;

    this.metadataFormValues[provider] = {};

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
      if (c.provider === provider) {
        c.isEditing = true;
        c.formValues = {}; 
        if (c.editableFieldsData) {
          c.editableFieldsData.forEach(f => {
            if (f.name === 'Active__c') {
                f.currentValue = true;
                this.metadataFormValues[provider]['Active__c'] = true;
            } else {
                f.currentValue = f.isCheckbox ? false : '';
            }
          });
        }
      }
      return c;
    });
  }

  handleAddMetadataCancel(event) {
    const provider = this.getProviderFromEvent(event);
    if (!provider) return;

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
      if (c.provider === provider) {
        c.isEditing = false;
        c.formValues = { ...c.fields };
        if (c.editableFieldsData) {
          c.editableFieldsData.forEach(field => {
            field.currentValue = c.fields[field.name];
          });
        }
      }
      return c;
    });
  }

  handleMetadataFieldChange(event) {
    const fieldName = event.target.dataset.field;
    const provider = event.target.dataset.provider;
    const isCheckbox = event.target.type === 'checkbox' || event.target.type === 'toggle';
    const value = isCheckbox ? event.target.checked : event.target.value;

    if (!fieldName || !provider) return;

    if (!this.metadataFormValues[provider]) {
      this.metadataFormValues[provider] = {};
    }
    this.metadataFormValues[provider][fieldName] = value;

    this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
      if (c.provider === provider) {
        if (!c.formValues) c.formValues = {};
        c.formValues[fieldName] = value;

        if (c.editableFieldsData) {
          c.editableFieldsData.forEach(f => {
            if (f.name === fieldName) {
              f.currentValue = value;
            }
          });
        }
      }
      return c;
    });
  }

  async handleMetadataSave(event) {
    const provider = event.target.dataset.provider || event.currentTarget.dataset.provider;
    if (!provider) return;

    this.isMetadataSaving = true;
    try {
      const formValues = this.metadataFormValues[provider] || {};
      const fieldValues = {};
      
      Object.keys(formValues).forEach((fieldName) => {
        let value = formValues[fieldName];
        if (fieldName === 'Active__c' || fieldName === 'UseSandbox__c') {
          value = (value === true || value === 'true');
        }
        fieldValues[fieldName] = value;
      });

      if (fieldValues['Active__c'] === undefined) {
          fieldValues['Active__c'] = true;
      }

      const payloadObject = { provider: provider, fieldValues: fieldValues };
      const response = await updatePaymentMetadata({ request: payloadObject });

      if (response && response.success) {
        this.metadataFormValues[provider] = { ...fieldValues };

        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
          if (c.provider === provider) {
            c.active = fieldValues['Active__c'];
            c.isEditing = false;
            c.formValues = { ...fieldValues };
            if (c.editableFieldsData) {
              c.editableFieldsData.forEach(f => {
                f.currentValue = fieldValues[f.name];
                f.displayValue = this.getFieldDisplayValue(f.name, fieldValues[f.name]);
              });
            }
          }
          return c;
        });

        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: `${provider} configuration saved!`, variant: 'success' }));
      } else {
        this.dispatchEvent(new ShowToastEvent({ title: 'Save Failed', message: response?.message || 'Server rejected the configuration.', variant: 'error' }));
      }
    } catch (error) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Apex Error', message: error?.body?.message || error?.message, variant: 'error' }));
    } finally {
      this.isMetadataSaving = false;
    }
  }

  async handleMetadataDelete(event) {
    const provider = event.target.dataset.provider || event.currentTarget.dataset.provider;
    if (!provider) return;

    if (!confirm(`Are you sure you want to delete the configuration for ${provider}?`)) {
        return;
    }

    this.isMetadataSaving = true;
    try {
      const config = this.paymentMetadataConfigs.find(c => c.provider === provider);
      const fieldValues = {};
      
      if (config && config.editableFieldsData) {
          config.editableFieldsData.forEach(field => {
              if (field.name === 'Active__c' || field.name === 'UseSandbox__c' || field.isCheckbox) {
                  fieldValues[field.name] = false;
              } else {
                  fieldValues[field.name] = null;
              }
          });
      }

      const payloadObject = { provider: provider, fieldValues: fieldValues };
      const response = await updatePaymentMetadata({ request: payloadObject });

      if (response && response.success) {
        this.metadataFormValues[provider] = {}; 

        this.paymentMetadataConfigs = this.paymentMetadataConfigs.map(c => {
          if (c.provider === provider) {
            c.active = false;
            c.isEditing = false;
            c.formValues = {};
            if (c.editableFieldsData) {
              c.editableFieldsData.forEach(f => {
                f.currentValue = f.isCheckbox ? false : '';
                f.displayValue = this.getFieldDisplayValue(f.name, f.currentValue);
              });
            }
          }
          return c;
        });

        this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', message: `${provider} configuration deleted successfully!`, variant: 'success' }));
      } else {
        this.dispatchEvent(new ShowToastEvent({ title: 'Delete Failed', message: response?.message || 'Server rejected the request.', variant: 'error' }));
      }
    } catch (error) {
      this.dispatchEvent(new ShowToastEvent({ title: 'Apex Error', message: error?.body?.message || error?.message, variant: 'error' }));
    } finally {
      this.isMetadataSaving = false;
    }
  }
}