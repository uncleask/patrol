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
    
    // 直接使用最新的报告文件名
    const latestReportId = 'patrol_report_20260421_175130';
    const date = '2026-04-21 17:51:30';
    
    // 加载最新报告获取详细信息
    fetch(`../output/${latestReportId}.json`)
        .then(response => response.json())
        .then(data => {
            const serverCount = data.servers.length;
            let alarmCount = 0;
            let seriousCount = 0;
            
            data.servers.forEach(server => {
                const serverInfo = server.results[0];
                if (serverInfo) {
                    alarmCount += serverInfo.result.warn_count + serverInfo.result.serious_count;
                    seriousCount += serverInfo.result.serious_count;
                }
            });
            
            // 生成日期卡片
            dateListContainer.innerHTML = '';
            const card = document.createElement('div');
            card.className = 'date-card';
            card.innerHTML = `
                <h3>${date}</h3>
                <p>服务器数量: ${serverCount}</p>
                <p>告警数量: ${alarmCount}</p>
                <p>严重告警: ${seriousCount}</p>
            `;
            
            // 添加告警徽章
            if (seriousCount > 0) {
                const badge = document.createElement('div');
                badge.className = 'alarm-badge serious';
                badge.textContent = `严重 ${seriousCount}`;
                card.appendChild(badge);
            } else if (alarmCount > 0) {
                const badge = document.createElement('div');
                badge.className = 'alarm-badge alarm';
                badge.textContent = `告警 ${alarmCount}`;
                card.appendChild(badge);
            }
            
            // 点击事件
            card.addEventListener('click', () => loadReport(latestReportId));
            
            dateListContainer.appendChild(card);
        })
        .catch(error => {
            console.error('加载报告失败:', error);
            dateListContainer.innerHTML = '<div class="error">加载报告失败</div>';
        });
}

// 加载报告详情
function loadReport(reportId) {
    const reportContent = document.getElementById('report-content');
    reportContent.innerHTML = '<div class="loading">加载中...</div>';
    
    // 从实际的JSON文件加载报告数据
    fetch(`../output/${reportId}.json`)
        .then(response => response.json())
        .then(report => {
            currentReport = report;
            displayReport(report);
            showPage('result-page');
        })
        .catch(error => {
            console.error('加载报告详情失败:', error);
            reportContent.innerHTML = '<div class="error">加载报告详情失败</div>';
        });
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
        // 获取服务器信息（新结构）
        const serverInfo = server.results[0];
        if (!serverInfo) return;
        
        content += `
            <div class="service-section">
                <h3>服务信息 - ${server.alias} (${server.ip})</h3>
                <p>巡检时间: ${serverInfo.time}</p>
                
                <!-- 系统信息 -->
                <div class="card">
                    <h4>系统信息</h4>
                    <table>
                        <tr>
                            <th>项目</th>
                            <th>值</th>
                        </tr>
                        <tr>
                            <td>主机名</td>
                            <td>${serverInfo.hostname}</td>
                        </tr>
                        <tr>
                            <td>IP地址</td>
                            <td>${serverInfo.hostip}</td>
                        </tr>
                        <tr>
                            <td>操作系统</td>
                            <td>${serverInfo.os}</td>
                        </tr>
                        <tr>
                            <td>系统启动时间</td>
                            <td>${serverInfo.uptimesince}</td>
                        </tr>
                        <tr>
                            <td>运行时长</td>
                            <td>${serverInfo.uptimeduration}</td>
                        </tr>
                    </table>
                </div>
                
                <!-- 资源信息 -->
                <div class="card">
                    <h4>资源信息</h4>
                    
                    <h5>CPU信息</h5>
                    <table>
                        <tr>
                            <th>项目</th>
                            <th>值</th>
                            <th>状态</th>
                        </tr>
                        <tr>
                            <td>使用率</td>
                            <td>${serverInfo.cpu.usage}${serverInfo.cpu.usage ? '%' : ''}</td>
                            <td class="status-${serverInfo.cpu.usestate}">
                                ${serverInfo.cpu.usestate}
                            </td>
                        </tr>
                        <tr>
                            <td>系统使用率</td>
                            <td>${serverInfo.cpu.sysusage}%</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>空闲率</td>
                            <td>${serverInfo.cpu.idle}%</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>IO等待</td>
                            <td>${serverInfo.cpu.iowait}%</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>平均负载</td>
                            <td>${serverInfo.cpu.avgload}</td>
                            <td></td>
                        </tr>
                    </table>
                    
                    <h5>内存信息</h5>
                    <table>
                        <tr>
                            <th>项目</th>
                            <th>值</th>
                            <th>状态</th>
                        </tr>
                        <tr>
                            <td>总内存</td>
                            <td>${serverInfo.memory.total}MB</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>已用内存</td>
                            <td>${serverInfo.memory.used}MB</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>空闲内存</td>
                            <td>${serverInfo.memory.free}MB</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>可用内存</td>
                            <td>${serverInfo.memory.available}MB</td>
                            <td></td>
                        </tr>
                        <tr>
                            <td>使用率</td>
                            <td>${serverInfo.memory.usage}${serverInfo.memory.usage ? '%' : ''}</td>
                            <td class="status-${serverInfo.memory.usestate}">
                                ${serverInfo.memory.usestate}
                            </td>
                        </tr>
                        <tr>
                            <td>交换空间</td>
                            <td>${serverInfo.memory.swaptotal}MB / 已用: ${serverInfo.memory.swapused}MB / 空闲: ${serverInfo.memory.swapfree}MB</td>
                            <td class="status-${serverInfo.memory.swapusestate}">
                                ${serverInfo.memory.swapusestate}
                            </td>
                        </tr>
                    </table>
                    
                    <h5>磁盘信息</h5>
                    <table>
                        <tr>
                            <th>挂载点</th>
                            <th>文件系统</th>
                            <th>总大小</th>
                            <th>已用</th>
                            <th>可用</th>
                            <th>使用率</th>
                            <th>状态</th>
                        </tr>
                        ${serverInfo.disk.map(disk => `
                            <tr>
                                <td>${disk.mounted}</td>
                                <td>${disk.filesystem}</td>
                                <td>${disk.total}</td>
                                <td>${disk.used}</td>
                                <td>${disk.available}</td>
                                <td>${disk.usage}${disk.usage ? '%' : ''}</td>
                                <td class="status-${disk.usestate}">
                                    ${disk.usestate}
                                </td>
                            </tr>
                        `).join('')}
                    </table>
                </div>
                
                <!-- 应用状态 -->
                <div class="card">
                    <h4>应用状态</h4>
                    <table>
                        <tr>
                            <th>应用名称</th>
                            <th>类型</th>
                            <th>用户</th>
                            <th>进程ID</th>
                            <th>状态</th>
                            <th>CPU使用率</th>
                            <th>内存使用率</th>
                            <th>运行时长</th>
                        </tr>
                        ${serverInfo.apps.length > 0 ? 
                            serverInfo.apps.map(app => `
                                <tr>
                                    <td>${app.name}</td>
                                    <td>${app.type}</td>
                                    <td>${app.user || 'N/A'}</td>
                                    <td>${app.pid || 'N/A'}</td>
                                    <td class="${app.state === 'running' ? 'status-normal' : 'status-serious'}">${app.state}</td>
                                    <td>${app.cpuusage || 'N/A'}%</td>
                                    <td>${app.memusage || 'N/A'}%</td>
                                    <td>${app.runtime || 'N/A'}</td>
                                </tr>
                            `).join('') : 
                            '<tr><td colspan="8">无应用</td></tr>'
                        }
                    </table>
                </div>
                
                <!-- Docker容器状态 -->
                <div class="card">
                    <h4>Docker容器状态</h4>
                    <table>
                        <tr>
                            <th>容器名称</th>
                            <th>容器ID</th>
                            <th>状态</th>
                            <th>详细状态</th>
                        </tr>
                        ${serverInfo.dockers.length > 0 ? 
                            serverInfo.dockers.map(container => {
                                let statusClass = '';
                                if (container.state === 'running') {
                                    statusClass = 'status-normal';
                                } else if (container.state === 'not_found') {
                                    statusClass = 'status-serious';
                                } else {
                                    statusClass = 'status-alarm';
                                }
                                
                                return `
                                    <tr>
                                        <td>${container.name}</td>
                                        <td>${container.id || 'N/A'}</td>
                                        <td class="${statusClass}">${container.state}</td>
                                        <td>${container.status || 'N/A'}</td>
                                    </tr>
                                `;
                            }).join('') : 
                            '<tr><td colspan="4">无容器</td></tr>'
                        }
                    </table>
                </div>
                
                <!-- 巡检结果 -->
                <div class="card">
                    <h4>巡检结果</h4>
                    <table>
                        <tr>
                            <th>项目</th>
                            <th>值</th>
                        </tr>
                        <tr>
                            <td>总检查项</td>
                            <td>${serverInfo.result.all_count}</td>
                        </tr>
                        <tr>
                            <td>正常</td>
                            <td>${serverInfo.result.normal_count}</td>
                        </tr>
                        <tr>
                            <td>警告</td>
                            <td>${serverInfo.result.warn_count}</td>
                        </tr>
                        <tr>
                            <td>严重</td>
                            <td>${serverInfo.result.serious_count}</td>
                        </tr>
                        <tr>
                            <td>状态描述</td>
                            <td>${serverInfo.result.description}</td>
                        </tr>
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
        const serverInfo = server.results[0];
        if (!serverInfo) return;
        
        if (serverInfo.cpu.usestate !== 'normal') count++;
        if (serverInfo.memory.usestate !== 'normal') count++;
        if (serverInfo.memory.swapusestate !== 'normal') count++;
        serverInfo.disk.forEach(disk => {
            if (disk.usestate !== 'normal') count++;
        });
        serverInfo.apps.forEach(app => {
            if (app.state !== 'running') count++;
        });
        serverInfo.dockers.forEach(container => {
            if (container.state !== 'running') count++;
        });
    });
    return count;
}

// 统计严重告警数量
function countSeriousAlarms(report) {
    let count = 0;
    report.servers.forEach(server => {
        const serverInfo = server.results[0];
        if (!serverInfo) return;
        
        if (serverInfo.cpu.usestate === 'serious') count++;
        if (serverInfo.memory.usestate === 'serious') count++;
        if (serverInfo.memory.swapusestate === 'serious') count++;
        serverInfo.disk.forEach(disk => {
            if (disk.usestate === 'serious') count++;
        });
        serverInfo.apps.forEach(app => {
            if (app.state !== 'running') count++;
        });
        serverInfo.dockers.forEach(container => {
            if (container.state === 'not_found') count++;
        });
    });
    return count;
}

// 收集告警信息
function collectAlarms(report) {
    const alarms = [];
    report.servers.forEach(server => {
        const serverInfo = server.results[0];
        if (!serverInfo) return;
        
        if (serverInfo.cpu.usestate !== 'normal') {
            alarms.push({
                server: server.alias,
                message: `CPU使用率过高 (${serverInfo.cpu.usage}%)`,
                status: serverInfo.cpu.usestate
            });
        }
        if (serverInfo.memory.usestate !== 'normal') {
            alarms.push({
                server: server.alias,
                message: `内存使用率过高 (${serverInfo.memory.usage}%)`,
                status: serverInfo.memory.usestate
            });
        }
        if (serverInfo.memory.swapusestate !== 'normal') {
            alarms.push({
                server: server.alias,
                message: `交换空间使用率过高`,
                status: serverInfo.memory.swapusestate
            });
        }
        serverInfo.disk.forEach(disk => {
            if (disk.usestate !== 'normal') {
                alarms.push({
                    server: server.alias,
                    message: `磁盘使用率过高 - ${disk.mounted} (${disk.usage}%)`,
                    status: disk.usestate
                });
            }
        });
        serverInfo.apps.forEach(app => {
            if (app.state !== 'running') {
                alarms.push({
                    server: server.alias,
                    message: `应用 ${app.name} 未运行`,
                    status: 'serious'
                });
            }
        });
        serverInfo.dockers.forEach(container => {
            if (container.state !== 'running') {
                alarms.push({
                    server: server.alias,
                    message: `容器 ${container.name} 状态异常 (${container.state})`,
                    status: container.state === 'not_found' ? 'serious' : 'alarm'
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