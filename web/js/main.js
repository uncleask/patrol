// 全局变量
let reports = [];

// 页面加载完成后执行
window.onload = function() {
    if (window.location.pathname.includes('index.html') || window.location.pathname.endsWith('/') || window.location.pathname.endsWith('/web/')) {
        loadReportList();
    } else if (window.location.pathname.includes('report.html')) {
        loadReportDetail();
    } else if (window.location.pathname.includes('trend.html')) {
        loadTrendData();
    }
};

// 加载报告列表
function loadReportList() {
    const dateListContainer = document.getElementById('report-list');
    dateListContainer.innerHTML = '<div class="loading">加载中...</div>';
    
    console.log('当前页面路径:', window.location.pathname);
    
    // 首先尝试获取目录列表
    const possibleListPaths = [
        'output/',
        '../output/',
        '../../output/',
        '/output/'
    ];
    
    function tryListPath(index) {
        if (index >= possibleListPaths.length) {
            console.log('无法获取目录列表，尝试使用已知报告');
            loadSingleReport();
            return;
        }
        
        const path = possibleListPaths[index];
        console.log('尝试获取目录:', path);
        
        fetch(path)
            .then(response => {
                if (!response.ok) throw new Error('目录不可访问');
                return response.text();
            })
            .then(html => {
                console.log('成功获取目录页面');
                parseReportList(html, path);
            })
            .catch(error => {
                console.log('路径', path, '获取目录失败:', error);
                tryListPath(index + 1);
            });
    }
    
    function loadSingleReport() {
        // 尝试直接使用我们现有的报告
        const reportId = 'patrol_report_20260421_175130';
        const date = '2026-04-21 17:51:30';
        
        // 尝试几种不同的路径
        const possiblePaths = [
            `output/${reportId}.json`,
            `../output/${reportId}.json`,
            `../../output/${reportId}.json`,
            `/output/${reportId}.json`
        ];
        
        function tryPath(pathIndex) {
            if (pathIndex >= possiblePaths.length) {
                console.error('所有路径都尝试失败');
                dateListContainer.innerHTML = '<div class="alert alert-danger">加载报告失败，请检查文件路径或网络连接</div>';
                return;
            }
            
            const path = possiblePaths[pathIndex];
            console.log('尝试路径:', path);
            
            fetch(path)
                .then(response => {
                    console.log('响应状态:', response.status);
                    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                    return response.text();
                })
                .then(text => {
                    try {
                        const data = JSON.parse(text);
                        console.log('成功加载JSON数据');
                        renderSingleReport(data, reportId, date);
                    } catch (e) {
                        console.error('JSON解析失败');
                        tryPath(pathIndex + 1);
                    }
                })
                .catch(error => {
                    console.error('路径', path, '失败:', error);
                    tryPath(pathIndex + 1);
                });
        }
        
        tryPath(0);
    }
    
    function parseReportList(html, basePath) {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const files = doc.querySelectorAll('a[href$=".json"]');
        
        if (files.length === 0) {
            console.log('目录中没有找到JSON文件，尝试加载单个报告');
            loadSingleReport();
            return;
        }
        
        console.log('找到', files.length, '个报告文件');
        
        const reportPromises = [];
        
        files.forEach(file => {
            const filename = file.getAttribute('href');
            if (filename.includes('')) return;
            
            const id = filename.replace('.json', '');
            const parts = id.split('_');
            let dateStr = '';
            let timeStr = '';
            
            if (parts.length >= 3) {
                dateStr = parts[1];
                timeStr = parts[2];
                dateStr = dateStr.substring(0,4) + '-' + dateStr.substring(4,6) + '-' + dateStr.substring(6,8);
                timeStr = timeStr.substring(0,2) + ':' + timeStr.substring(2,4) + ':' + timeStr.substring(4,6);
            }
            
            const reportPromise = fetch(basePath + filename)
                .then(response => response.json())
                .then(data => {
                    return {
                        id: id,
                        filename: filename,
                        date: dateStr || '未知日期',
                        time: timeStr || '未知时间',
                        data: data
                    };
                })
                .catch(error => {
                    console.error('加载报告失败:', filename, error);
                    return null;
                });
            
            reportPromises.push(reportPromise);
        });
        
        Promise.all(reportPromises)
            .then(reportList => {
                const validReports = reportList.filter(r => r !== null);
                validReports.sort((a, b) => {
                    const dateA = a.date + ' ' + a.time;
                    const dateB = b.date + ' ' + b.time;
                    return new Date(dateB) - new Date(dateA);
                });
                
                reports = validReports;
                renderReportList(basePath);
            })
            .catch(error => {
                console.error('加载报告列表失败:', error);
                loadSingleReport();
            });
    }
    
    function renderSingleReport(data, reportId, date) {
        let serverCount = 0;
        let totalCount = 0;
        let normalCount = 0;
        let warnCount = 0;
        let seriousCount = 0;
        
        if (Array.isArray(data)) {
            serverCount = data.length;
            data.forEach(server => {
                if (server.result) {
                    totalCount += server.result.all_count || 0;
                    normalCount += server.result.normal_count || 0;
                    warnCount += server.result.warn_count || 0;
                    seriousCount += server.result.serious_count || 0;
                }
            });
        } else if (data.servers) {
            serverCount = data.servers.length;
            data.servers.forEach(server => {
                const serverInfo = server.results ? server.results[0] : server;
                if (serverInfo && serverInfo.result) {
                    totalCount += serverInfo.result.all_count || 0;
                    normalCount += serverInfo.result.normal_count || 0;
                    warnCount += serverInfo.result.warn_count || 0;
                    seriousCount += serverInfo.result.serious_count || 0;
                }
            });
        }
        
        dateListContainer.innerHTML = '';
        const card = document.createElement('div');
        card.className = 'report-item';
        
        let statusClass = 'status-pass';
        if (seriousCount > 0) statusClass = 'status-fail';
        else if (warnCount > 0) statusClass = 'status-warn';
        
        card.innerHTML = `
            <h3>${date}</h3>
            <p>服务器数量: ${serverCount}</p>
            <p>检查项: 总计 ${totalCount} | 正常 ${normalCount} | 警告 ${warnCount} | 严重 ${seriousCount}</p>
            <p>状态: <span class="${statusClass}">${seriousCount > 0 ? '有严重问题' : warnCount > 0 ? '有警告' : '正常'}</span></p>
            <div class="links">
                <a href="report.html?id=${reportId}">查看详情</a>
            </div>
        `;
        
        dateListContainer.appendChild(card);
    }
    
    function renderReportList(basePath) {
        dateListContainer.innerHTML = '';
        
        reports.forEach(report => {
            let serverCount = 0;
            let totalCount = 0;
            let normalCount = 0;
            let warnCount = 0;
            let seriousCount = 0;
            const data = report.data;
            
            if (Array.isArray(data)) {
                serverCount = data.length;
                data.forEach(server => {
                    if (server.result) {
                        totalCount += server.result.all_count || 0;
                        normalCount += server.result.normal_count || 0;
                        warnCount += server.result.warn_count || 0;
                        seriousCount += server.result.serious_count || 0;
                    }
                });
            } else if (data.servers) {
                serverCount = data.servers.length;
                data.servers.forEach(server => {
                    const serverInfo = server.results ? server.results[0] : server;
                    if (serverInfo && serverInfo.result) {
                        totalCount += serverInfo.result.all_count || 0;
                        normalCount += serverInfo.result.normal_count || 0;
                        warnCount += serverInfo.result.warn_count || 0;
                        seriousCount += serverInfo.result.serious_count || 0;
                    }
                });
            }
            
            const card = document.createElement('div');
            card.className = 'report-item';
            
            let statusClass = 'status-pass';
            if (seriousCount > 0) statusClass = 'status-fail';
            else if (warnCount > 0) statusClass = 'status-warn';
            
            card.innerHTML = `
                <h3>${report.date} ${report.time}</h3>
                <p>服务器数量: ${serverCount}</p>
                <p>检查项: 总计 ${totalCount} | 正常 ${normalCount} | 警告 ${warnCount} | 严重 ${seriousCount}</p>
                <p>状态: <span class="${statusClass}">${seriousCount > 0 ? '有严重问题' : warnCount > 0 ? '有警告' : '正常'}</span></p>
                <div class="links">
                    <a href="report.html?id=${report.id}">查看详情</a>
                </div>
            `;
            
            dateListContainer.appendChild(card);
        });
    }
    
    tryListPath(0);
}

// 加载报告详情
function loadReportDetail() {
    const urlParams = new URLSearchParams(window.location.search);
    const reportId = urlParams.get('id');
    
    if (!reportId) {
        const alertList = document.getElementById('alert-list');
        if (alertList) alertList.innerHTML = '<p>请选择要查看的报告</p>';
        return;
    }
    
    console.log('当前页面路径:', window.location.pathname);
    
    // 尝试几种不同的路径
    const possiblePaths = [
        `output/${reportId}.json`,
        `../output/${reportId}.json`,
        `../../output/${reportId}.json`,
        `/output/${reportId}.json`
    ];
    
    // 按顺序尝试路径
    function tryPath(index) {
        if (index >= possiblePaths.length) {
            console.error('所有路径都尝试失败');
            const alertList = document.getElementById('alert-list');
            if (alertList) alertList.innerHTML = '<p>加载报告失败，请重试</p>';
            return;
        }
        
        const path = possiblePaths[index];
        console.log('尝试路径:', path);
        
        fetch(path)
            .then(response => {
                console.log('响应状态:', response.status);
                if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                return response.text();
            })
            .then(text => {
                try {
                    const data = JSON.parse(text);
                    console.log('成功加载JSON数据');
                    renderReportDetail(data);
                } catch (e) {
                    console.error('JSON解析失败');
                    tryPath(index + 1);
                }
            })
            .catch(error => {
                console.error('路径', path, '失败:', error);
                tryPath(index + 1);
            });
    }
    
    tryPath(0);
}

// 渲染报告详情
function renderReportDetail(data) {
    // 更新报告时间
    const now = new Date();
    const reportTime = now.toLocaleString('zh-CN');
    const reportDateEl = document.getElementById('report-time');
    const reportDateEl2 = document.getElementById('report-date');
    if (reportDateEl) reportDateEl.textContent = reportTime;
    if (reportDateEl2) reportDateEl2.textContent = '巡检报告日期: ' + now.toLocaleDateString('zh-CN');
    
    // 统计信息
    let totalChecks = 0;
    let normalChecks = 0;
    let warningChecks = 0;
    let errorChecks = 0;
    
    // 告警信息
    const alertList = [];
    
    // 处理每个服务器的数据
    let servers = [];
    if (Array.isArray(data)) {
        servers = data;
    } else if (data.servers) {
        servers = data.servers;
    }
    
    servers.forEach(server => {
        if (server.error) {
            // 处理错误情况
            alertList.push({
                host: (server.alias || server.hostname || 'Unknown') + ' (' + (server.ip || server.hostip || 'Unknown') + ')',
                message: `【错误】${server.message}`
            });
            return;
        }

        const serverInfo = server.results ? server.results[0] : server;
        
        // 计算检查项数量
        if (serverInfo.cpu) {
            totalChecks++;
            if (serverInfo.cpu.usestate === 'normal') normalChecks++;
            else if (serverInfo.cpu.usestate === 'warn') warningChecks++;
            else errorChecks++;

            if (serverInfo.cpu.usestate !== 'normal') {
                alertList.push({
                    host: (server.hostname || server.alias || 'Unknown') + ' (' + (server.hostip || server.ip || 'Unknown') + ')',
                    message: `【${serverInfo.cpu.usestate === 'warn' ? '告警' : '严重'}】CPU 状态异常 - 使用率: ${serverInfo.cpu.usage}%, 状态: ${serverInfo.cpu.usestate}`
                });
            }
        }

        if (serverInfo.memory) {
            totalChecks++;
            if (serverInfo.memory.usestate === 'normal') normalChecks++;
            else if (serverInfo.memory.usestate === 'warn') warningChecks++;
            else errorChecks++;

            if (serverInfo.memory.usestate !== 'normal') {
                alertList.push({
                    host: (server.hostname || server.alias || 'Unknown') + ' (' + (server.hostip || server.ip || 'Unknown') + ')',
                    message: `【${serverInfo.memory.usestate === 'warn' ? '告警' : '严重'}】内存 状态异常 - 使用率: ${serverInfo.memory.usage}%, 状态: ${serverInfo.memory.usestate}`
                });
            }
        }

        if (serverInfo.disk && Array.isArray(serverInfo.disk)) {
            serverInfo.disk.forEach(disk => {
                totalChecks++;
                if (disk.usestate === 'normal') normalChecks++;
                else if (disk.usestate === 'warn') warningChecks++;
                else errorChecks++;

                if (disk.usestate !== 'normal') {
                    alertList.push({
                        host: (server.hostname || server.alias || 'Unknown') + ' (' + (server.hostip || server.ip || 'Unknown') + ')',
                        message: `【${disk.usestate === 'warn' ? '告警' : '严重'}】磁盘 状态异常 - 挂载点: ${disk.mounted}, 使用率: ${disk.usage}%, 状态: ${disk.usestate}`
                    });
                }
            });
        }

        if (serverInfo.apps && Array.isArray(serverInfo.apps)) {
            serverInfo.apps.forEach(app => {
                totalChecks++;
                if (app.state === 'running') normalChecks++;
                else if (app.state === 'warn') warningChecks++;
                else errorChecks++;

                if (app.state !== 'running') {
                    alertList.push({
                        host: (server.hostname || server.alias || 'Unknown') + ' (' + (server.hostip || server.ip || 'Unknown') + ')',
                        message: `【${app.state === 'warn' ? '告警' : '严重'}】应用状态异常 - ${app.name}: ${app.state}`
                    });
                }
            });
        }

        if (serverInfo.dockers && Array.isArray(serverInfo.dockers)) {
            serverInfo.dockers.forEach(docker => {
                totalChecks++;
                if (docker.state === 'running' || docker.state === 'exited') normalChecks++;
                else if (docker.state === 'warn') warningChecks++;
                else errorChecks++;

                if (docker.state !== 'running' && docker.state !== 'exited') {
                    alertList.push({
                        host: (server.hostname || server.alias || 'Unknown') + ' (' + (server.hostip || server.ip || 'Unknown') + ')',
                        message: `【${docker.state === 'warn' ? '告警' : '严重'}】Docker 状态异常 - ${docker.name}: ${docker.state}`
                    });
                }
            });
        }
    });
    
    // 更新统计信息
    const totalChecksEl = document.getElementById('total-checks');
    const normalChecksEl = document.getElementById('normal-checks');
    const warningChecksEl = document.getElementById('warning-checks');
    const errorChecksEl = document.getElementById('error-checks');
    
    if (totalChecksEl) totalChecksEl.textContent = totalChecks;
    if (normalChecksEl) normalChecksEl.textContent = normalChecks;
    if (warningChecksEl) warningChecksEl.textContent = warningChecks;
    if (errorChecksEl) errorChecksEl.textContent = errorChecks;
    
    // 渲染告警信息
    const alertListElement = document.getElementById('alert-list');
    if (alertListElement) {
        if (alertList.length > 0) {
            // 按主机分组告警信息
            const alertsByHost = {};
            alertList.forEach(alert => {
                if (!alertsByHost[alert.host]) {
                    alertsByHost[alert.host] = [];
                }
                alertsByHost[alert.host].push(alert.message);
            });
            
            let alertHtml = '';
            Object.keys(alertsByHost).forEach(host => {
                alertHtml += `
                    <div class="alert-item">
                        <div class="host">【${host}】</div>
                        <div class="messages">${alertsByHost[host].join(' | ')}</div>
                    </div>
                `;
            });
            alertListElement.innerHTML = alertHtml;
        } else {
            alertListElement.innerHTML = '<p>暂无告警信息</p>';
        }
    }
    
    // 渲染主机信息
    const hostsSection = document.getElementById('hosts-section');
    if (hostsSection) {
        let hostsHtml = '';
        
        servers.forEach(server => {
            if (server.error) {
                hostsHtml += `
                    <div class="host-section">
                        <h2>主机: ${server.alias || server.hostname || 'Unknown'} (${server.ip || server.hostip || 'Unknown'})</h2>
                        <div class="alert-item">
                            <div class="host">错误信息</div>
                            <div class="messages">${server.message}</div>
                        </div>
                    </div>
                `;
                return;
            }

            const serverInfo = server.results ? server.results[0] : server;
            
            let cpuUsage = serverInfo.cpu ? serverInfo.cpu.usage : 'N/A';
            let cpuState = serverInfo.cpu ? serverInfo.cpu.usestate : 'normal';
            let memUsage = serverInfo.memory ? serverInfo.memory.usage : 'N/A';
            let memState = serverInfo.memory ? serverInfo.memory.usestate : 'normal';
            let uptime = server.uptimeduration || serverInfo.uptimesince || 'N/A';
            let os = server.os || serverInfo.os || 'N/A';
            let serverName = server.hostname || server.alias || 'Unknown';
            let serverIp = server.hostip || server.ip || 'Unknown';

            hostsHtml += `
                <div class="host-section">
                    <h2>主机: ${serverName} (${serverIp})</h2>
                    
                    <div class="host-info">
                        <div class="host-info-item">
                            <div class="label">运行时间</div>
                            <div class="value">${uptime}</div>
                        </div>
                        <div class="host-info-item">
                            <div class="label">操作系统</div>
                            <div class="value">${os}</div>
                        </div>
                        <div class="host-info-item">
                            <div class="label">检查时间</div>
                            <div class="value">${server.time || serverInfo.time || 'N/A'}</div>
                        </div>
                    </div>
                    
                    <div class="status-cards">
                        <div class="status-card">
                            <h3>CPU状态</h3>
                            <div class="status-item">
                                <div class="label">使用率</div>
                                <div class="value">${cpuUsage}%</div>
                                <div class="progress-bar">
                                    <div class="progress progress-${cpuState === 'normal' ? 'green' : cpuState === 'warn' ? 'yellow' : 'red'}" style="width: ${parseInt(cpuUsage) || 0}%"></div>
                                </div>
                            </div>
                            <div class="status-item">
                                <div class="label">平均负载</div>
                                <div class="value">${serverInfo.cpu ? serverInfo.cpu.avgload : 'N/A'}</div>
                            </div>
                        </div>
                        
                        <div class="status-card">
                            <h3>内存状态</h3>
                            <div class="status-item">
                                <div class="label">使用率</div>
                                <div class="value">${serverInfo.memory ? (serverInfo.memory.usage_text || memUsage + '%') : 'N/A'}</div>
                                <div class="progress-bar">
                                    <div class="progress progress-${memState === 'normal' ? 'green' : memState === 'warn' ? 'yellow' : 'red'}" style="width: ${parseInt(memUsage) || 0}%"></div>
                                </div>
                            </div>
                            <div class="status-item">
                                <div class="label">Swap使用率</div>
                                <div class="value">${serverInfo.memory ? (serverInfo.memory.swapusage_text || serverInfo.memory.swapusage + '%') : 'N/A'}</div>
                            </div>
                        </div>
                        
                        <div class="status-card">
                            <h3>磁盘使用状态</h3>
                            ${serverInfo.disk && Array.isArray(serverInfo.disk) ? serverInfo.disk.map(disk => `
                                <div class="status-item">
                                    <div class="label">${disk.mounted}</div>
                                    <div class="value">${disk.usage}% (${disk.used}/${disk.total})</div>
                                    <div class="progress-bar">
                                        <div class="progress progress-${disk.usestate === 'normal' ? 'green' : disk.usestate === 'warn' ? 'yellow' : 'red'}" style="width: ${parseInt(disk.usage) || 0}%"></div>
                                    </div>
                                </div>
                            `).join('') : '<div class="status-item"><div class="label">磁盘</div><div class="value">N/A</div></div>'}
                        </div>
                    </div>
            `;
            
            if (serverInfo.result) {
                hostsHtml += `
                    <div class="result-card">
                        <h3>巡检结果</h3>
                        <div class="result-item"><strong>总计:</strong> ${serverInfo.result.all_count || 0}</div>
                        <div class="result-item"><strong>正常:</strong> ${serverInfo.result.normal_count || 0}</div>
                        <div class="result-item"><strong>警告:</strong> ${serverInfo.result.warn_count || 0}</div>
                        <div class="result-item"><strong>严重:</strong> ${serverInfo.result.serious_count || 0}</div>
                        ${serverInfo.result.description && serverInfo.result.description !== '【正常】' ? `
                            <div class="result-description">${serverInfo.result.description}</div>
                        ` : ''}
                    </div>
                `;
            }
            
            if (serverInfo.apps && Array.isArray(serverInfo.apps)) {
                hostsHtml += `
                    <div class="service-list">
                        <h3>应用状态</h3>
                        <table class="service-table">
                            <thead>
                                <tr>
                                    <th>进程名</th>
                                    <th>服务名称</th>
                                    <th>进程ID</th>
                                    <th>进程序态</th>
                                    <th>运行时长</th>
                                    <th>CPU使用率</th>
                                    <th>内存使用率</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${serverInfo.apps.map(app => `
                                    <tr>
                                        <td>${app.name}</td>
                                        <td>${app.name}</td>
                                        <td>${app.pid || '-'}</td>
                                        <td class="status-${app.state}">${app.state}</td>
                                        <td>${app.runtime || 'unknown'}</td>
                                        <td>${app.cpuusage || '0.0'}%</td>
                                        <td>${app.memusage || '0.0'}%</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                `;
            }
            
            if (serverInfo.dockers && Array.isArray(serverInfo.dockers)) {
                hostsHtml += `
                    <div class="docker-list">
                        <h3>Docker容器状态</h3>
                        <table class="docker-table">
                            <thead>
                                <tr>
                                    <th>容器名称</th>
                                    <th>服务名称</th>
                                    <th>容器ID</th>
                                    <th>状态</th>
                                    <th>运行时长</th>
                                    <th>CPU使用率</th>
                                    <th>内存使用率</th>
                                    <th>内存使用量</th>
                                </tr>
                            </thead>
                            <tbody>
                                ${serverInfo.dockers.map(docker => `
                                    <tr>
                                        <td>${docker.name}</td>
                                        <td>${docker.name}</td>
                                        <td>${docker.id || '-'}</td>
                                        <td class="status-${docker.state}">${docker.status || docker.state}</td>
                                        <td>${docker.runtime || 'unknown'}</td>
                                        <td>${docker.cpuusage || '0.0'}%</td>
                                        <td>${docker.memusage || '0.0'}%</td>
                                        <td>${docker.memused || '-'}</td>
                                    </tr>
                                `).join('')}
                            </tbody>
                        </table>
                    </div>
                `;
            }
            
            hostsHtml += `
                </div>
            `;
        });
        
        hostsSection.innerHTML = hostsHtml;
    }
}

// 加载趋势数据
function loadTrendData() {
    const content = document.getElementById('content');
    content.innerHTML = `
        <h2>巡检趋势分析</h2>
        <div class="chart-container">
            <h3>资源使用趋势</h3>
            <canvas id="resourceChart" width="800" height="400"></canvas>
        </div>
        <div class="chart-container">
            <h3>告警趋势</h3>
            <canvas id="alertChart" width="800" height="400"></canvas>
        </div>
    `;
    
    const mockTrendData = {
        dates: ['2026-04-19', '2026-04-20', '2026-04-21'],
        cpuUsage: [12, 8, 6.5],
        memoryUsage: [15, 13, 12.2],
        diskUsage: [7, 6, 6],
        alertCount: [5, 4, 4]
    };
    
    drawResourceChart(mockTrendData);
    drawAlertChart(mockTrendData);
}

// 绘制资源使用趋势图
function drawResourceChart(data) {
    const canvas = document.getElementById('resourceChart');
    if (!canvas) return;
    
    const ctx = canvas.getContext('2d');
    const width = canvas.width;
    const height = canvas.height;
    const padding = 60;
    
    ctx.clearRect(0, 0, width, height);
    
    const xScale = (width - padding * 2) / (data.dates.length - 1);
    const yScale = (height - padding * 2) / 100;
    
    ctx.beginPath();
    ctx.strokeStyle = '#e5e7eb';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 5; i++) {
        const y = padding + i * (height - padding * 2) / 5;
        ctx.moveTo(padding, y);
        ctx.lineTo(width - padding, y);
    }
    ctx.stroke();
    
    ctx.beginPath();
    ctx.strokeStyle = '#374151';
    ctx.lineWidth = 2;
    ctx.moveTo(padding, padding);
    ctx.lineTo(padding, height - padding);
    ctx.lineTo(width - padding, height - padding);
    ctx.stroke();
    
    const colors = ['#667eea', '#10b981', '#f59e0b'];
    const labels = ['CPU使用率', '内存使用率', '磁盘使用率'];
    const datasets = [data.cpuUsage, data.memoryUsage, data.diskUsage];
    
    datasets.forEach((dataset, dataIndex) => {
        ctx.beginPath();
        ctx.strokeStyle = colors[dataIndex];
        ctx.lineWidth = 3;
        
        dataset.forEach((value, index) => {
            const x = padding + index * xScale;
            const y = height - padding - value * yScale;
            
            if (index === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });
        
        ctx.stroke();
        
        dataset.forEach((value, index) => {
            const x = padding + index * xScale;
            const y = height - padding - value * yScale;
            
            ctx.beginPath();
            ctx.fillStyle = colors[dataIndex];
            ctx.arc(x, y, 6, 0, Math.PI * 2);
            ctx.fill();
        });
    });
    
    ctx.fillStyle = '#374151';
    ctx.font = '14px -apple-system, BlinkMacSystemFont, sans-serif';
    ctx.textAlign = 'center';
    data.dates.forEach((date, index) => {
        const x = padding + index * xScale;
        ctx.fillText(date, x, height - 20);
    });
    
    ctx.textAlign = 'right';
    for (let i = 0; i <= 100; i += 20) {
        const y = height - padding - i * yScale;
        ctx.fillText(i + '%', padding - 10, y + 5);
    }
    
    ctx.textAlign = 'left';
    labels.forEach((label, index) => {
        ctx.fillStyle = colors[index];
        ctx.fillRect(padding + index * 150, 20, 20, 20);
        ctx.fillStyle = '#374151';
        ctx.fillText(label, padding + 25 + index * 150, 35);
    });
}

// 绘制告警趋势图
function drawAlertChart(data) {
    const canvas = document.getElementById('alertChart');
    if (!canvas) return;
    
    const ctx = canvas.getContext('2d');
    const width = canvas.width;
    const height = canvas.height;
    const padding = 60;
    
    ctx.clearRect(0, 0, width, height);
    
    const barWidth = (width - padding * 2) / data.dates.length * 0.6;
    const maxAlert = Math.max(...data.alertCount, 1);
    const yScale = (height - padding * 2) / maxAlert;
    
    ctx.beginPath();
    ctx.strokeStyle = '#374151';
    ctx.lineWidth = 2;
    ctx.moveTo(padding, padding);
    ctx.lineTo(padding, height - padding);
    ctx.lineTo(width - padding, height - padding);
    ctx.stroke();
    
    data.alertCount.forEach((count, index) => {
        const x = padding + (index * (width - padding * 2) / data.dates.length) + (barWidth * 0.2);
        const barHeight = count * yScale;
        const y = height - padding - barHeight;
        
        const gradient = ctx.createLinearGradient(x, y, x, height - padding);
        gradient.addColorStop(0, '#667eea');
        gradient.addColorStop(1, '#764ba2');
        
        ctx.fillStyle = gradient;
        ctx.fillRect(x, y, barWidth, barHeight);
        
        ctx.fillStyle = '#1f2937';
        ctx.font = 'bold 14px -apple-system, BlinkMacSystemFont, sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText(count, x + barWidth / 2, y - 10);
        
        ctx.font = '14px -apple-system, BlinkMacSystemFont, sans-serif';
        ctx.fillText(data.dates[index], x + barWidth / 2, height - 25);
    });
    
    ctx.textAlign = 'right';
    ctx.fillStyle = '#374151';
    for (let i = 0; i <= maxAlert; i++) {
        const y = height - padding - i * yScale;
        ctx.fillText(i.toString(), padding - 10, y + 5);
    }
}
