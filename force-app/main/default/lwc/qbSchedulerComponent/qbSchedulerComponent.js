import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getScheduledJobs from '@salesforce/apex/QBSchedulerController.getScheduledJobs';
import scheduleJob from '@salesforce/apex/QBSchedulerController.scheduleJob';
import stopJob from '@salesforce/apex/QBSchedulerController.stopJob';
import getSyncSettingsSummary from '@salesforce/apex/QBSchedulerController.getSyncSettingsSummary';
import getRecentRuns from '@salesforce/apex/QBSchedulerController.getRecentRuns';
import togglePauseStatus from '@salesforce/apex/QBSchedulerController.togglePauseStatus';
import deleteSpecificJob from '@salesforce/apex/QBSchedulerController.deleteSpecificJob';
import editSpecificJob from '@salesforce/apex/QBSchedulerController.editSpecificJob';
import getUsageSummary from '@salesforce/apex/SchedulerEntitlementService.getUsageSummary';
export default class QbSchedulerComponent extends LightningElement {
    @track isNewScheduleView = false;
    @track frequency = '10';
    @track hasJobs = false;
    wiredJobsResult;

    @track searchKey = '';
    @track statusFilter = 'all';
    @track allJobs = [];
    @track filteredJobs = [];
    @track selectedJobId = null;
    @track syncSettings = { objects: '', direction: '', type: '' };
    @track freqValue = '10';
    @track freqType = 'Minutes';
    @track recentRuns = [];
    @track usageSummary = { activeCount: 0, maxActiveSchedules: 10, remaining: 10, limitReached: false, message: '' };
    wiredUsageResult;

    statusOptions = [
        { label: 'All Status', value: 'all' },
        { label: 'Active', value: 'active' },
        { label: 'Paused', value: 'paused' }
    ];

    frequencyOptions = [
        { label: '5', value: '5' },
        { label: '10', value: '10' },
        { label: '15', value: '15' },
        { label: '30', value: '30' },
        { label: '60', value: '60' }
    ];

    @wire(getScheduledJobs)
    wiredJobs(result) {
        this.wiredJobsResult = result;
        if (result.data) {
            this.hasJobs = result.data.length > 0;
            this.allJobs = result.data.map(job => {
                let displayStatus = 'Inactive';
                let badgeClass = 'badge-inactive';

                if (job.status === 'WAITING' || job.status === 'ACQUIRED' || job.status === 'EXECUTING') {
                    displayStatus = 'Active';
                    badgeClass = 'badge-active';
                } else if (job.status === 'PAUSED' || job.status === 'PAUSED_AND_WAITING') {
                    displayStatus = 'Paused';
                    badgeClass = 'badge-paused';
                }

                return {
                    ...job,
                    displayStatus: displayStatus,
                    badgeClass: badgeClass
                };
            });


            this.applyFilters();
        } else if (result.error) {
            console.error('Error fetching jobs:', result.error);
        }
    }

    @wire(getSyncSettingsSummary)
    wiredSettings({ error, data }) {
        if (data) {
            this.syncSettings = data;
        } else if (error) {
            console.error('Error fetching sync settings:', error);
        }
    }

    @wire(getRecentRuns, { jobId: '$selectedJobId' })
    wiredRecentRuns({ error, data }) {
        if (data) {
            this.recentRuns = data;
        } else if (error) {
            console.error('Error fetching recent runs:', error);
            this.recentRuns = [];
        }
    }

    @wire(getUsageSummary)
    wiredUsage(result) {
        this.wiredUsageResult = result;
        if (result.data) {
            this.usageSummary = result.data;
        } else if (result.error) {
            console.error('Error fetching schedule usage:', result.error);
        }
    }

    get usageCounterText() {
        return `${this.usageSummary.activeCount} / ${this.usageSummary.maxActiveSchedules}`;
    }

    get usageCardClass() {
        return this.usageSummary.limitReached ? 'usage-card usage-card-limit' : 'usage-card';
    }

    get isScheduleLimitReached() {
        return this.usageSummary.limitReached === true;
    }

    get hasRecentRuns() {
        return this.recentRuns && this.recentRuns.length > 0;
    }

    handleSearch(event) {
        this.searchKey = event.target.value.toLowerCase();
        this.applyFilters();
    }

    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
        this.applyFilters();
    }

    applyFilters() {
        this.filteredJobs = this.allJobs.filter(job => {
            const matchesSearch = job.name.toLowerCase().includes(this.searchKey);
            const matchesStatus = this.statusFilter === 'all' ||
                job.displayStatus.toLowerCase() === this.statusFilter.toLowerCase();
            return matchesSearch && matchesStatus;
        }).map(job => ({
            ...job,
            cardClass: job.id === this.selectedJobId ? 'job-item active-job' : 'job-item'
        }));
    }

    handleJobSelect(event) {
        this.selectedJobId = event.currentTarget.dataset.id;
        this.applyFilters();
    }

    handleFrequencyChange(event) {
        this.frequency = event.detail.value;
    }

    handleNewSchedule() {
        if (this.isScheduleLimitReached) {
            this.showToast('Schedule Limit Reached', this.usageSummary.message, 'warning');
            return;
        }
        this.isNewScheduleView = true;
        this.syncObjects = this.syncObjects.map(obj => {
            return {
                ...obj,
                isSelected: true,
                btnClass: 'obj-btn selected'
            };
        });
        this.freqValue = '10';
        this.freqType = 'Minutes';
    }

    handleBackToList() {
        this.isNewScheduleView = false;
        return refreshApex(this.wiredJobsResult);
    }

    async handleSetSchedule() {
        try {
            const selectedObj = this.syncObjects.find(obj => obj.isSelected);
            console.log(JSON.stringify(selectedObj));
            const objectNameToSend = selectedObj ? selectedObj.id : 'Accounts';
            const newCreatedJobId = await scheduleJob({
                freqValue: this.freqValue,
                freqType: this.freqType,
                selectedObject: objectNameToSend
            });

            this.showToast('Success', 'Schedule created successfully!', 'success');

            this.selectedJobId = newCreatedJobId;
            this.isNewScheduleView = false;

            await refreshApex(this.wiredJobsResult);
            await refreshApex(this.wiredUsageResult);

        } catch (error) {
            this.showToast('Error', error.body?.message, 'error');
        }
    }

    async handleStopSchedule() {
        try {
            const result = await stopJob();
            this.showToast('Schedule Stopped', result, 'info');
            await refreshApex(this.wiredUsageResult);
            return refreshApex(this.wiredJobsResult);
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get selectedJob() {
        if (this.allJobs && this.selectedJobId) {
            return this.allJobs.find(job => job.id === this.selectedJobId);
        }
        return null;
    }

    get freqTypeOptions() {
        return [
            { label: 'Minutes', value: 'Minutes' },
            { label: 'Hours', value: 'Hours' },
            { label: 'Days', value: 'Days' },
            { label: 'Weeks', value: 'Weeks' },
            { label: 'Months', value: 'Months' }
        ];
    }

    handleValueChange(event) {
        this.freqValue = event.target.value;
    }

    handleTypeChange(event) {
        this.freqType = event.detail.value;
    }

    @track syncObjects = [
        { id: 'Accounts', label: 'Accounts', icon: 'utility:user', isSelected: true, btnClass: 'obj-btn selected' },
        { id: 'Vendors', label: 'Vendors', icon: 'utility:company', isSelected: false, btnClass: 'obj-btn' },
        { id: 'Products', label: 'Products', icon: 'utility:products', isSelected: false, btnClass: 'obj-btn' },
        { id: 'Orders', label: 'Orders', icon: 'utility:orders', isSelected: false, btnClass: 'obj-btn' },
        { id: 'Invoices', label: 'Invoices', icon: 'utility:file', isSelected: false, btnClass: 'obj-btn' },
        { id: 'CreditMemos', label: 'Credit Memos', icon: 'utility:money', isSelected: false, btnClass: 'obj-btn' },
        { id: 'PurchaseOrders', label: 'Purchase Orders', icon: 'utility:cart', isSelected: false, btnClass: 'obj-btn' }
    ];

    toggleObjectSelection(event) {
        const selectedId = event.currentTarget.dataset.id;
        this.syncObjects = this.syncObjects.map(obj => {
            return {
                ...obj,
                isSelected: obj.id === selectedId,
                btnClass: obj.id === selectedId ? 'obj-btn selected' : 'obj-btn'
            };
        });
    }
    @track isEditMode = false;
    @track editFreqValue = '10';
    @track editFreqType = 'Minutes';

    handleEdit() {
        this.isEditMode = true; // Edit mode ON
    }

    handleCancelEdit() {
        this.isEditMode = false; // Edit mode OFF
    }

    handleEditValueChange(event) {
        this.editFreqValue = event.target.value;
    }

    handleEditTypeChange(event) {
        this.editFreqType = event.detail.value;
    }

    async handlePause() {
        const isCurrentlyPaused = this.selectedJob?.displayStatus === 'Paused';
        try {
            await togglePauseStatus({ pauseIt: !isCurrentlyPaused });
            this.showToast('Success', !isCurrentlyPaused ? 'Scheduler Paused Successfully' : 'Scheduler Resumed!', 'success');
            return refreshApex(this.wiredJobsResult);
        } catch (error) {
            this.showToast('Error', error.body?.message, 'error');
        }
    }

    get latestRunStats() {
        if (this.recentRuns && this.recentRuns.length > 0) {
            return this.recentRuns[0];
        }
        return {
            status: 'N/A',
            processed: 0,
            failed: 0,
            icon: 'utility:info',
            variant: ''
        };
    }

    get pauseButtonLabel() {
        return this.selectedJob?.displayStatus === 'Paused' ? 'Resume Schedule' : 'Pause Schedule';
    }

    async handleDelete() {
        try {
            await deleteSpecificJob({ jobName: this.selectedJob.name });
            this.showToast('Success', 'Schedule deleted successfully', 'success');

            this.selectedJobId = null;
            this.isEditMode = false;
            await refreshApex(this.wiredUsageResult);
            return refreshApex(this.wiredJobsResult);
        } catch (error) {
            this.showToast('Error', error.body?.message, 'error');
        }
    }

    async handleSaveEdit() {
        try {
            await editSpecificJob({
                jobName: this.selectedJob.name,
                freqValue: this.editFreqValue,
                freqType: this.editFreqType
            });
            this.showToast('Success', 'Schedule updated successfully!', 'success');
            this.isEditMode = false;
            await refreshApex(this.wiredUsageResult);
            return refreshApex(this.wiredJobsResult);
        } catch (error) {
            this.showToast('Error', error.body?.message, 'error');
        }
    }

    @track isSfToQboSync = true; 

    handleSyncDirectionToggle(event) {
        this.isSfToQboSync = event.target.checked;
    }
}