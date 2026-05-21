import { LightningElement, track } from 'lwc';

export default class QuickBridgeLogin extends LightningElement {
    @track userId = '';

    handleUserIdChange(event) {
        this.userId = event.target.value;
    }

    // Handles typing and auto-advancing to the next PIN input
    handlePinInput(event) {
        const input = event.target;
        const index = parseInt(input.dataset.index, 10);
        
        // Strip non-numeric characters
        let value = input.value.replace(/[^0-9]/g, '');
        if (value.length > 1) {
            value = value.slice(0, 1);
        }
        input.value = value;

        // Auto-advance logic
        if (value.length === 1 && index < 3) {
            const nextInput = this.template.querySelector(`.pin-input[data-index="${index + 1}"]`);
            if (nextInput) {
                nextInput.removeAttribute('disabled');
                nextInput.focus();
            }
        }
    }

    // Handles backspace auto-retreat functionality
    handlePinKeydown(event) {
        const input = event.target;
        const index = parseInt(input.dataset.index, 10);

        if (event.key === 'Backspace') {
            if (!input.value && index > 0) {
                // If current is empty, move back to previous and clear it
                const prevInput = this.template.querySelector(`.pin-input[data-index="${index - 1}"]`);
                if (prevInput) {
                    prevInput.focus();
                    prevInput.value = '';
                    input.setAttribute('disabled', 'true');
                }
            }
        }
    }

    handleLogin(event) {
        event.preventDefault(); // Prevent standard form submission reload
        
        const pinInputs = this.template.querySelectorAll('.pin-input');
        let fullPin = '';
        pinInputs.forEach(input => {
            fullPin += input.value;
        });

        // Basic validation
        if (!this.userId || fullPin.length !== 4) {
            // In a production app, use LightningAlert or ShowToastEvent here
            console.warn('Please enter a valid User ID and 4-Digit PIN.');
            return;
        }

        // Dispatch Custom Event to parent component or aura wrapper
        this.dispatchEvent(new CustomEvent('loginattempt', {
            detail: {
                userId: this.userId,
                pin: fullPin
            }
        }));
    }

    handleForgotPin(event) {
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('forgotpin'));
    }
}