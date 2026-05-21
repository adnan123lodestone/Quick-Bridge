import { LightningElement, track } from 'lwc';

export default class QbDashboard extends LightningElement {
    @track dashboardStats = [
        { id: '1', title: 'Total Records', subtitle: 'Total number of records synchronized.', value: '49728', icon: 'utility:database', colorClass: 'bg-blue' },
        { id: '2', title: 'Successful Sync Records', subtitle: 'Number of records successfully synchronized.', value: '47242', icon: 'utility:success', colorClass: 'bg-green' },
        { id: '3', title: 'Error Records', subtitle: 'Number of records that encountered errors during synchronization.', value: '2486', icon: 'utility:error', colorClass: 'bg-red' },
        { id: '4', title: 'Customers', subtitle: 'Number of customer records.', value: '2508', icon: 'utility:groups', colorClass: 'bg-purple' },
        { id: '5', title: 'Vendors', subtitle: 'Number of vendor records.', value: '383', icon: 'utility:user', colorClass: 'bg-teal' },
        { id: '6', title: 'Products', subtitle: 'Number of product records.', value: '2513', icon: 'utility:product', colorClass: 'bg-light-green' },
        { id: '7', title: 'Quotes', subtitle: 'Number of quote records.', value: '1458', icon: 'utility:contract', colorClass: 'bg-orange' },
        { id: '8', title: 'Purchase Orders', subtitle: 'Number of purchase order records.', value: '3096', icon: 'utility:cart', colorClass: 'bg-dark-blue' },
        { id: '9', title: 'Invoices', subtitle: 'Number of invoice records.', value: '38902', icon: 'utility:page', colorClass: 'bg-brown' },
        { id: '10', title: 'Credit Memos', subtitle: 'Number of credit memo records.', value: '517', icon: 'utility:moneybag', colorClass: 'bg-teal-light' }
    ];
}