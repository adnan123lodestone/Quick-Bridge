import { api, LightningElement, track } from 'lwc';
import getReportingSummary from '@salesforce/apex/IntegrationUsageService.getReportingSummary';

const PRODUCT_ALIASES = {
    qbo: 'quickbooks',
    quickbooksonline: 'quickbooks',
    quickbooks: 'quickbooks',
    shopify: 'shopify',
    stripe: 'stripe',
    authorizenet: 'authorizenet',
    authnet: 'authorizenet',
    paypal: 'paypal',
    fedex: 'fedex',
    ups: 'ups'
};

export default class IntegrationReportingDashboard extends LightningElement {
    @api selectedProductKey = '';
    @api subscribedProductKeys = [];
    @api availableProductKeys = [];

    @track products = [];
    isLoading = false;
    errorMessage = '';

    connectedCallback() {
        this.loadSummary();
    }

    get hasError() {
        return this.errorMessage !== '';
    }

    get hasProductContext() {
        return this.normalizedSelectedProductKey !== '';
    }

    get normalizedSelectedProductKey() {
        return this.normalizeProductKey(this.selectedProductKey);
    }

    get selectedProduct() {
        return this.products.find(product => product.productKey === this.normalizedSelectedProductKey);
    }

    get subscribedProducts() {
        if (this.hasProductContext) {
            return [];
        }

        return this.products.filter(product => this.isSubscribedProduct(product));
    }

    get availableProducts() {
        if (this.hasProductContext) {
            return [];
        }

        return this.products.filter(product => !this.isSubscribedProduct(product));
    }

    get showAllProductGroups() {
        return !this.hasProductContext;
    }

    get emptySelectedProduct() {
        return this.hasProductContext && !this.selectedProduct && !this.isLoading;
    }

    async loadSummary() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            const rows = await getReportingSummary();
            this.products = (rows || []).map(row => this.decorateProduct(row));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Could not load reporting metrics.';
        } finally {
            this.isLoading = false;
        }
    }

    decorateProduct(row) {
        const statusVariant = (row.subscriptionStatus || 'Inactive').toLowerCase().replace(/\s+/g, '-');
        const days = row.subscriptionDaysRemaining;

        const product = {
            ...row,
            statusClass: `status-badge status-${statusVariant}`,
            daysText: days === null || days === undefined ? 'No expiry date configured' : `${days} day${days === 1 ? '' : 's'} remaining`,
            lastUpdatedText: row.lastUpdatedAt ? `Updated ${new Date(row.lastUpdatedAt).toLocaleString()}` : 'Not updated yet'
        };
        product.metricCards = this.buildMetricCards(product);
        return product;
    }

    buildMetricCards(product) {
        return [
            this.buildMetric('Synced Records', product.recordSyncCount, product.recordSyncLimit, 'utility:database'),
            this.buildMetric('Errors', product.errorCount, null, 'utility:error'),
            this.buildMetric('Endpoint Usage', product.endpointUsageCount, product.endpointUsageLimit, 'utility:connected_apps'),
            this.buildMetric('Task Usage', product.taskUsageCount, product.taskUsageLimit, 'utility:task'),
            this.buildMetric('Active Schedules', product.activeScheduleCount, product.activeScheduleLimit, 'utility:clock'),
            this.buildMetric('Subscription', product.subscriptionStatus, null, 'utility:date_input')
        ];
    }

    buildMetric(label, value, limit, icon) {
        const numericValue = typeof value === 'number' ? value : null;
        const numericLimit = typeof limit === 'number' ? limit : null;
        const hasLimit = numericLimit !== null && numericLimit > 0 && numericValue !== null;
        const percent = hasLimit ? Math.min(100, Math.round((numericValue / numericLimit) * 100)) : 0;

        return {
            label,
            value: numericValue === null ? value : this.formatNumber(numericValue),
            icon,
            hasLimit,
            barStyle: `width: ${percent}%;`,
            ariaLabel: `${label} ${percent}% used`,
            limitText: hasLimit ? `${this.formatNumber(numericValue)} of ${this.formatNumber(numericLimit)} used` : ''
        };
    }

    formatNumber(value) {
        return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(value || 0);
    }

    isSubscribedProduct(product) {
        const subscribedKeys = this.normalizeKeyList(this.subscribedProductKeys);
        const availableKeys = this.normalizeKeyList(this.availableProductKeys);
        if (subscribedKeys.length > 0 || availableKeys.length > 0) {
            return subscribedKeys.includes(product.productKey);
        }

        return product.subscriptionStatus === 'Active' || product.subscriptionStatus === 'Expiring Soon';
    }

    normalizeKeyList(value) {
        if (Array.isArray(value)) {
            return value.map(item => this.normalizeProductKey(item)).filter(Boolean);
        }
        if (typeof value === 'string' && value) {
            return value.split(',').map(item => this.normalizeProductKey(item)).filter(Boolean);
        }
        return [];
    }

    normalizeProductKey(value) {
        const normalized = (value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
        return PRODUCT_ALIASES[normalized] || normalized;
    }
}