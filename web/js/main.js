// 全局变量
let currentReport = null;
let charts = {};

// 初始化页面
function initPage() {
    // 设置当前时间
    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);
    
    // 绑定导航事件
    bindNavigationEvents();
    
    // 加载日期列表
    loadDateList();
    
    // 绑定刷新按钮
    document.getElementById('refresh-btn').addEventListener('click', loadDateList);
}

// 更新当前时间
function updateCurrentTime() {
    const now = new Date();
    const timeString = now.toLocaleString('zh-CN', {
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });
    document.getElementById('current-time').textContent = timeString;
}

// 绑定导航事件
function bindNavigationEvents() {
    // 日期列表导航
    document.getElementById('nav-dates').addEventListener('click', function(e) {
        e.preventDefault();
        showPage('dates-page');
    });
    
    // 趋势分析导航
    document.getElementById('nav-trend').addEventListener('click', function(e) {
        e.preventDefault();
        showPage('trend-page');
        initCharts();
    });
    
    // 返回日期列表按钮
    document.getElementById('back-to-dates').addEventListener('click', function() {
        showPage('dates-page');
    });
    
    // 生成趋势按钮
    document.getElementById('generate-trend').addEventListener('click', generateTrend);
}

// 显示指定页面
function showPage(pageId) {
    // 隐藏所有页面
    document.querySelectorAll('.page').forEach(page => {
        page.classList.remove('active');
    });
    
    // 显示指定页面
    document.getElementById(pageId).classList.add('active');
}

// 加载日期列表
function loadDateList() {
    const dateListContainer = document.getElementById('date-list');
    dateListContainer.innerHTML = '<div class="loading">加载中...</div>';
    
    // 模拟从 output 目录加载报告
    // 实际项目中，这里应该通过后端 API 获取文件列表
    setTimeout(() => {
        // 模拟报告数据
        const reports = [
            {
                id: 'patrol_report_20260420_154831',
                date: '2026-04-20 15:48:31',
                servers: 1,
                alarms: 2,
                serious: 1
            },
            {
                id: 'patrol_report_20260420_154200',
                date: '2026-04-20 15:42:00',
                servers: 1,
                alarms: 1,
                serious: 0
            },
            {
                id: 'patrol_report_20260420_143407',
                date: '2026-04-20 14:34:07',
                servers: 1,
                alarms: 0,
                serious: 0
            }
        ];
        
        // 生成日期卡片
        dateListContainer.innerHTML = '';
        reports.forEach(report => {
            const card = document.createElement('div');
            card.className = 'date-card';
            card.innerHTML = `
                <h3>${report.date}</h3>
                <p>服务器数量: ${report.servers}</p>
                <p>告警数量: ${report.alarms}</p>
                <p>严重告警: ${report.serious}</p>
            `;
            
            // 添加告警徽章
            if (report.serious > 0) {
                const badge = document.createElement('div');
                badge.className = 'alarm-badge serious';
                badge.textContent = `严重 ${report.serious}`;
                card.appendChild(badge);
            } else if (report.alarms > 0) {
                const badge = document.createElement('div');
                badge.className = 'alarm-badge alarm';
                badge.textContent = `告警 ${report.alarms}`;
                card.appendChild(badge);
            }
            
            // 点击事件
            card.addEventListener('click', () => loadReport(report.id));
            
            dateListContainer.appendChild(card);
        });
    }, 1000);
}

// 加载报告详情
function loadReport(reportId) {
    const reportContent = document.getElementById('report-content');
    reportContent.innerHTML = '<div class="loading">加载中...</div>';
    
    // 模拟加载报告数据
    setTimeout(() => {
        // 模拟报告数据
        const report = {
            timestamp: '2026-04-20T15:48:31',
            servers: [{
                alias: 'localserv',
                ip: '127.0.0.1',
                groups: 'group_local',
                results: {
                    system_info: {
                        os_version: 'Ubuntu 24.04.3 LTS',
                        kernel_version: '6.18.5',
                        uptime: 'up 7:56',
                        cpu_arch: '64位'
                    },
                    resource_info: {
                        cpu: { usage: 100, alarm_status: 'serious' },
                        memory: { total_mb: 5974, used_mb: 731, usage_percent: 12.24, alarm_status: 'normal' },
                        disks: [{
                            filesystem: 'none',
                            size: '1.5T',
                            used: '84G',
                            available: '1.3T',
                            use_percent: 6,
                            mount_point: '/',
                            alarm_status: 'normal'
                        }]
                    },
                    app_info: {
                        processes: [{
                            process_name: 'sshd',
                            service_name: 'SSH服务',
                            running: false
                        }, {
                            process_name: 'cron',
                            service_name: '定时任务服务',
                            running: false
                        }],
                        docker_containers: []
                    },
                    checks: [{
                        name: 'cpu',
                        type: 'cpu',
                        value: '%Cpu(s):  0.0 us,  0.0 sy,  0.0 ni,100.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st ',
                        status: 'normal'
                    }, {
                        name: 'mem',
                        type: 'mem',
                        value: 'total: 5974MB, used: 735MB',
                        status: 'serious'
                    }]
                }
            }]
        };
        
        currentReport = report;
        displayReport(report);
        showPage('result-page');
    }, 1000);
}

// 显示报告详情
function displayReport(report) {
    const reportContent = document.getElementById('report-content');
    const reportTitle = document.getElementById('report-title');
    
    // 设置报告标题
    const timestamp = new Date(report.timestamp);
    reportTitle.textContent = `巡检报告 - ${timestamp.toLocaleString('zh-CN')}`;
    
    // 生成报告内容
    let content = '';
    
    // 汇总信息
    content += `
        <div class="summary-section">
            <h3>巡检汇总信息</h3>
            <div class="summary-grid">
                <div class="summary-item">
                    <div class="label">巡检时间</div>
                    <div class="value">${timestamp.toLocaleString('zh-CN')}</div>
                </div>
                <div class="summary-item">
                    <div class="label">服务器数量</div>
                    <div class="value">${report.servers.length}</div>
                </div>
                <div class="summary-item">
                    <div class="label">告警数量</div>
                    <div class="value">${countAlarms(report)}</div>
                </div>
                <div class="summary-item">
                    <div class="label">严重告警</div>
                    <div class="value">${countSeriousAlarms(report)}</div>
                </div>
            </div>
        </div>
    `;
    
    // 告警信息
    const alarms = collectAlarms(report);
    if (alarms.length > 0) {
        content += `
            <div class="alarm-section">
                <h3>巡检告警信息</h3>
                <ul class="alarm-list">
        `;
        alarms.forEach(alarm => {
            content += `
                <li class="alarm-item ${alarm.status}">
                    <strong>${alarm.server}</strong>: ${alarm.message} (${alarm.status})
                </li>
            `;
        });
        content += `
                </ul>
            </div>
        `;
    }
    
    // 服务器信息
    report.servers.forEach(server => {
        content += `
            <div class="service-section">
                <h3>服务信息 - ${server.alias} (${server.ip})</h3>
                
                <!-- 系统信息 -->
                <div class="card">
                    <h4>系统信息</h4>
                    <table>
                        <tr>
                            <th>项目</th>
                            <th>值</th>
                        </tr>
                        <tr>
                            <td>操作系统版本</td>
                            <td>${server.results.system_info.os_version}</td>
                        </tr>
                        <tr>
                            <td>内核版本</td>
                            <td>${server.results.system_info.kernel_version}</td>
                        </tr>
                        <tr>
                            <td>运行时长</td>
                            <td>${server.results.system_info.uptime}</td>
                        </tr>
                        <tr>
                            <td>CPU架构</td>
                            <td>${server.results.system_info.cpu_arch}</td>
                        </tr>
                    </table>
                </div>
                
                <!-- 资源信息 -->
                <div class="card">
                    <h4>资源信息</h4>
                    <table>
                        <tr>
                            <th>资源</th>
                            <th>使用率</th>
                            <th>状态</th>
                        </tr>
                        <tr>
                            <td>CPU</td>
                            <td>${server.results.resource_info.cpu.usage}%</td>
                            <td class="status-${server.results.resource_info.cpu.alarm_status}">
                                ${server.results.resource_info.cpu.alarm_status}
                            </td>
                        </tr>
                        <tr>
                            <td>内存</td>
                            <td>${server.results.resource_info.memory.usage_percent.toFixed(2)}%</td>
                            <td class="status-${server.results.resource_info.memory.alarm_status}">
                                ${server.results.resource_info.memory.alarm_status}
                            </td>
                        </tr>
                    </table>
                    
                    <h5>磁盘信息</h5>
                    <table>
                        <tr>
                            <th>文件系统</th>
                            <th>大小</th>
                            <th>已用</th>
                            <th>可用</th>
                            <th>使用率</th>
                            <th>状态</th>
                        </tr>
                        ${server.results.resource_info.disks.map(disk => `
                            <tr>
                                <td>${disk.filesystem}</td>
                                <td>${disk.size}</td>
                                <td>${disk.used}</td>
                                <td>${disk.available}</td>
                                <td>${disk.use_percent}%</td>
                                <td class="status-${disk.alarm_status}">
                                    ${disk.alarm_status}
                                </td>
                            </tr>
                        `).join('')}
                    </table>
                </div>
                
                <!-- 虚机进程列表 -->
                <div class="card">
                    <h4>虚机进程列表</h4>
                    <table>
                        <tr>
                            <th>进程名</th>
                            <th>服务名</th>
                            <th>运行状态</th>
                        </tr>
                        ${server.results.app_info.processes.map(process => `
                            <tr>
                                <td>${process.process_name}</td>
                                <td>${process.service_name}</td>
                                <td>${process.running ? '运行中' : '未运行'}</td>
                            </tr>
                        `).join('')}
                    </table>
                </div>
                
                <!-- 容器进程列表 -->
                <div class="card">
                    <h4>容器进程列表</h4>
                    <table>
                        <tr>
                            <th>容器名</th>
                            <th>服务名</th>
                            <th>运行状态</th>
                        </tr>
                        ${server.results.app_info.docker_containers.length > 0 ? 
                            server.results.app_info.docker_containers.map(container => `
                                <tr>
                                    <td>${container.container_name}</td>
                                    <td>${container.service_name}</td>
                                    <td>${container.state}</td>
                                </tr>
                            `).join('') : 
                            '<tr><td colspan="3">无容器</td></tr>'
                        }
                    </table>
                </div>
            </div>
        `;
    });
    
    reportContent.innerHTML = content;
}

// 统计告警数量
function countAlarms(report) {
    let count = 0;
    report.servers.forEach(server => {
        if (server.results.resource_info.cpu.alarm_status !== 'normal') count++;
        if (server.results.resource_info.memory.alarm_status !== 'normal') count++;
        server.results.resource_info.disks.forEach(disk => {
            if (disk.alarm_status !== 'normal') count++;
        });
    });
    return count;
}

// 统计严重告警数量
function countSeriousAlarms(report) {
    let count = 0;
    report.servers.forEach(server => {
        if (server.results.resource_info.cpu.alarm_status === 'serious') count++;
        if (server.results.resource_info.memory.alarm_status === 'serious') count++;
        server.results.resource_info.disks.forEach(disk => {
            if (disk.alarm_status === 'serious') count++;
        });
    });
    return count;
}

// 收集告警信息
function collectAlarms(report) {
    const alarms = [];
    report.servers.forEach(server => {
        if (server.results.resource_info.cpu.alarm_status !== 'normal') {
            alarms.push({
                server: server.alias,
                message: `CPU使用率过高 (${server.results.resource_info.cpu.usage}%)`,
                status: server.results.resource_info.cpu.alarm_status
            });
        }
        if (server.results.resource_info.memory.alarm_status !== 'normal') {
            alarms.push({
                server: server.alias,
                message: `内存使用率过高 (${server.results.resource_info.memory.usage_percent.toFixed(2)}%)`,
                status: server.results.resource_info.memory.alarm_status
            });
        }
        server.results.resource_info.disks.forEach(disk => {
            if (disk.alarm_status !== 'normal') {
                alarms.push({
                    server: server.alias,
                    message: `磁盘使用率过高 - ${disk.mount_point} (${disk.use_percent}%)`,
                    status: disk.alarm_status
                });
            }
        });
    });
    return alarms;
}

// 初始化图表
function initCharts() {
    // 销毁旧图表
    Object.values(charts).forEach(chart => chart.destroy());
    
    // 初始化 CPU 图表
    const cpuCtx = document.getElementById('cpu-chart').getContext('2d');
    charts.cpu = new Chart(cpuCtx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'CPU 使用率 (%)',
                data: [],
                borderColor: '#4361ee',
                backgroundColor: 'rgba(67, 97, 238, 0.1)',
                tension: 0.3,
                fill: true
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100
                }
            }
        }
    });
    
    // 初始化内存图表
    const memCtx = document.getElementById('mem-chart').getContext('2d');
    charts.mem = new Chart(memCtx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: '内存使用率 (%)',
                data: [],
                borderColor: '#3a0ca3',
                backgroundColor: 'rgba(58, 12, 163, 0.1)',
                tension: 0.3,
                fill: true
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100
                }
            }
        }
    });
    
    // 初始化磁盘图表
    const diskCtx = document.getElementById('disk-chart').getContext('2d');
    charts.disk = new Chart(diskCtx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: '磁盘使用率 (%)',
                data: [],
                borderColor: '#7209b7',
                backgroundColor: 'rgba(114, 9, 183, 0.1)',
                tension: 0.3,
                fill: true
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    max: 100
                }
            }
        }
    });
    
    // 初始化告警图表
    const alarmCtx = document.getElementById('alarm-chart').getContext('2d');
    charts.alarm = new Chart(alarmCtx, {
        type: 'bar',
        data: {
            labels: [],
            datasets: [{
                label: '告警数量',
                data: [],
                backgroundColor: '#f72585',
            }, {
                label: '严重告警',
                data: [],
                backgroundColor: '#4cc9f0',
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                }
            },
            scales: {
                y: {
                    beginAtZero: true
                }
            }
        }
    });
}

// 生成趋势
function generateTrend() {
    const period = document.getElementById('trend-period').value;
    
    // 模拟趋势数据
    const labels = [];
    const cpuData = [];
    const memData = [];
    const diskData = [];
    const alarmData = [];
    const seriousData = [];
    
    // 生成模拟数据
    for (let i = 7; i >= 0; i--) {
        const date = new Date();
        date.setDate(date.getDate() - i);
        
        if (period === 'day') {
            labels.push(date.toLocaleDateString('zh-CN'));
        } else if (period === 'week') {
            labels.push(`第${Math.floor(date.getDay()/7)+1}周`);
        } else {
            labels.push(`${date.getMonth()+1}月`);
        }
        
        cpuData.push(Math.random() * 100);
        memData.push(Math.random() * 100);
        diskData.push(Math.random() * 100);
        alarmData.push(Math.floor(Math.random() * 5));
        seriousData.push(Math.floor(Math.random() * 3));
    }
    
    // 更新图表数据
    charts.cpu.data.labels = labels;
    charts.cpu.data.datasets[0].data = cpuData;
    charts.cpu.update();
    
    charts.mem.data.labels = labels;
    charts.mem.data.datasets[0].data = memData;
    charts.mem.update();
    
    charts.disk.data.labels = labels;
    charts.disk.data.datasets[0].data = diskData;
    charts.disk.update();
    
    charts.alarm.data.labels = labels;
    charts.alarm.data.datasets[0].data = alarmData;
    charts.alarm.data.datasets[1].data = seriousData;
    charts.alarm.update();
}

// 页面加载完成后初始化
window.addEventListener('DOMContentLoaded', initPage);