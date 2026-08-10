import { api, LightningElement } from "lwc";

export default class Select extends LightningElement {
  @api disabled;
  @api label;
  @api messageWhenValueMissing;
  @api multiple;
  @api name;
  @api options;
  @api required;
  @api size;
  @api validity;
  @api value;
  @api variant;

  @api checkValidity() {}
  @api reportValidity() {}
  @api setCustomValidity() {}
}
