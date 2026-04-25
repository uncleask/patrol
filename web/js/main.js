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
    
    // 尝试直接使用我们现有的报告
    const reportId = 'patrol_report_20260421_175130';
    const date = '2026-04-21 17:51:30';
    
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
            dateListContainer.innerHTML = '<div class="alert alert-danger">加载报告失败，请检查文件路径或网络连接</div>';
            return;
        }
        
        const path = possiblePaths[index];
        console.log('尝试路径:', path);
        
        fetch(path)
            .then(response => {
                console.log('响应状态:', response.status);
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                return response.text();
            })
            .then(text => {
                try {
                    const data = JSON.parse(text);
                    console.log('成功加载JSON数据');
                    const serverCount = data.servers.length;
                    let totalCount = 0;
                    let normalCount = 0;
                    let warnCount = 0;
                    let seriousCount = 0;
                    
                    data.servers.forEach(server => {
                        const serverInfo = server.results[0];
                        if (serverInfo && serverInfo.result) {
                            totalCount += serverInfo.result.all_count || 0;
                            normalCount += serverInfo.result.normal_count || 0;
                            warnCount += serverInfo.result.warn_count || 0;
                            seriousCount += serverInfo.result.serious_count || 0;
                        }
                    });
                    
                    // 渲染报告列表
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
                } catch (e) {
                    console.error('JSON解析失败，文本内容:', text.substring(0, 200));
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

// 加载报告详情
function loadReportDetail() {
    const urlParams = new URLSearchParams(window.location.search);
    const reportId = urlParams.get('id');
    
    if (!reportId) {
        document.getElementById('content').innerHTML = '<div class="alert alert-danger"><h3>错误</h3><p>未指定报告ID</p></div>';
        return;
    }
    
    const content = document.getElementById('content');
    content.innerHTML = '<p>正在加载报告详情...</p>';
    
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
            content.innerHTML = '<div class="alert alert-danger"><h3>错误</h3><p>加载报告失败，请检查文件路径或网络连接</p></div>';
            return;
        }
        
        const path = possiblePaths[index];
        console.log('尝试路径:', path);
        
        fetch(path)
            .then(response => {
                console.log('响应状态:', response.status);
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                return response.text();
            })
            .then(text => {
                try {
                    const data = JSON.parse(text);
                    console.log('成功加载JSON数据');
                    renderReportDetail(data, reportId);
                } catch (e) {
                    console.error('JSON解析失败，文本内容:', text.substring(0, 200));
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
function renderReportDetail(data, reportId) {
    const content = document.getElementById('content');
    if (!content) return;
    
    let totalCount = 0;
    let normalCount = 0;
    let warnCount = 0;
    let seriousCount = 0;
    const alerts = [];
    
    data.servers.forEach(server => {
        const serverInfo = server.results[0];
        if (!serverInfo) return;
        
        if (serverInfo.result) {
            totalCount += serverInfo.result.all_count || 0;
            normalCount += serverInfo.result.normal_count || 0;
            warnCount += serverInfo.result.warn_count || 0;
            seriousCount += serverInfo.result.serious_count || 0;
        }
        
        const serverName = server.alias || 'Unknown';
        const serverIp = server.ip || 'Unknown';
        
        if (serverInfo.cpu && serverInfo.cpu.usestate !== 'normal') {
            alerts.push({
                server: serverName,
                ip: serverIp,
                message: `CPU使用率过高: ${serverInfo.cpu.usage}%`,
                status: serverInfo.cpu.usestate
            });
        }
        
        if (serverInfo.memory && serverInfo.memory.usestate !== 'normal') {
            alerts.push({
                server: serverName,
                ip: serverIp,
                message: `内存使用率过高: ${serverInfo.memory.usage}%`,
                status: serverInfo.memory.usestate
            });
        }
        
        if (serverInfo.disk) {
            serverInfo.disk.forEach(disk => {
                if (disk.usestate !== 'normal') {
                    alerts.push({
                        server: serverName,
                        ip: serverIp,
                        message: `磁盘使用率过高 - ${disk.mounted}: ${disk.usage}%`,
                        status: disk.usestate
                    });
                }
            });
        }
        
        if (serverInfo.apps) {
            serverInfo.apps.forEach(app => {
                if (app.state !== 'running') {
                    alerts.push({
                        server: serverName,
                        ip: serverIp,
                        message: `应用 ${app.name} 状态: ${app.state}`,
                        status: 'serious'
                    });
                }
            });
        }
        
        if (serverInfo.dockers) {
            serverInfo.dockers.forEach(docker => {
                if (docker.state !== 'running') {
                    alerts.push({
                        server: serverName,
                        ip: serverIp,
                        message: `Docker容器 ${docker.name} 状态: ${docker.state}`,
                        status: docker.state === 'not_found' ? 'serious' : 'warn'
                    });
                }
            });
        }
    });
    
    let html = `
        <div class="summary">
            <h2>巡检汇总信息</h2>
            <div class="summary-item"><strong>报告生成时间:</strong> ${new Date(data.timestamp).toLocaleString('zh-CN')}</div>
            <div class="summary-item"><strong>服务器数量:</strong> ${data.servers.length}</div>
            <div class="summary-item"><strong>检查项:</strong> 总计 ${totalCount}</div>
            <div class="summary-item"><strong>正常:</strong> <span class="status-pass">${normalCount}</span></div>
            <div class="summary-item"><strong>警告:</strong> <span class="status-warn">${warnCount}</span></div>
            <div class="summary-item"><strong>严重:</strong> <span class="status-fail">${seriousCount}</span></div>
        </div>
    `;
    
    if (alerts.length > 0) {
        const hasSerious = alerts.some(a => a.status === 'serious');
        html += `
            <div class="alert ${hasSerious ? 'alert-danger' : 'alert-warning'}">
                <h3>巡检告警信息 (${alerts.length}条)</h3>
                <ul>
                    ${alerts.map(alert => `<li><strong>[${alert.server} (${alert.ip})]</strong> ${alert.message}</li>`).join('')}
                </ul>
            </div>
        `;
    }
    
    data.servers.forEach(server => {
        const serverInfo = server.results[0];
        if (!serverInfo) return;
        
        const serverName = server.alias || 'Unknown';
        const serverIp = server.ip || 'Unknown';
        
        html += `
            <div class="server-section">
                <div class="server-header">服务器: ${serverName} (${serverIp})</div>
                <table>
                    <tr>
                        <th>检查项</th>
                        <th>详情</th>
                        <th>状态</th>
                    </tr>
        `;
        
        if (serverInfo.os) {
            html += `
                <tr>
                    <td>操作系统</td>
                    <td>${serverInfo.os}</td>
                    <td><span class="status-pass">正常</span></td>
                </tr>
            `;
        }
        
        if (serverInfo.uptimesince) {
            html += `
                <tr>
                    <td>系统启动时间</td>
                    <td>${serverInfo.uptimesince}</td>
                    <td><span class="status-pass">正常</span></td>
                </tr>
            `;
        }
        
        if (serverInfo.cpu) {
            let statusClass = 'status-pass';
            if (serverInfo.cpu.usestate === 'warn') statusClass = 'status-warn';
            if (serverInfo.cpu.usestate === 'serious') statusClass = 'status-fail';
            
            html += `
                <tr>
                    <td>CPU使用率</td>
                    <td>使用率: ${serverInfo.cpu.usage}% | 平均负载: ${serverInfo.cpu.avgload}</td>
                    <td><span class="${statusClass}">${serverInfo.cpu.usestate}</span></td>
                </tr>
            `;
        }
        
        if (serverInfo.memory) {
            let statusClass = 'status-pass';
            if (serverInfo.memory.usestate === 'warn') statusClass = 'status-warn';
            if (serverInfo.memory.usestate === 'serious') statusClass = 'status-fail';
            
            html += `
                <tr>
                    <td>内存使用</td>
                    <td>已用: ${serverInfo.memory.used}MB / 总量: ${serverInfo.memory.total}MB (${serverInfo.memory.usage}%)</td>
                    <td><span class="${statusClass}">${serverInfo.memory.usestate}</span></td>
                </tr>
            `;
        }
        
        if (serverInfo.disk && serverInfo.disk.length > 0) {
            serverInfo.disk.forEach((disk, index) => {
                let statusClass = 'status-pass';
                if (disk.usestate === 'warn') statusClass = 'status-warn';
                if (disk.usestate === 'serious') statusClass = 'status-fail';
                
                html += `
                    <tr>
                        <td>磁盘 ${disk.mounted}</td>
                        <td>已用: ${disk.used} / 总量: ${disk.total} (${disk.usage}%)</td>
                        <td><span class="${statusClass}">${disk.usestate}</span></td>
                    </tr>
                `;
            });
        }
        
        if (serverInfo.apps && serverInfo.apps.length > 0) {
            serverInfo.apps.forEach(app => {
                let statusClass = app.state === 'running' ? 'status-pass' : 'status-fail';
                
                html += `
                    <tr>
                        <td>应用 ${app.name}</td>
                        <td>状态: ${app.state} | PID: ${app.pid || '-'} | CPU: ${app.cpuusage || '-'}% | MEM: ${app.memusage || '-'}%</td>
                        <td><span class="${statusClass}">${app.state}</span></td>
                    </tr>
                `;
            });
        }
        
        if (serverInfo.dockers && serverInfo.dockers.length > 0) {
            serverInfo.dockers.forEach(docker => {
                let statusClass = docker.state === 'running' ? 'status-pass' : 'status-fail';
                
                html += `
                    <tr>
                        <td>Docker容器 ${docker.name}</td>
                        <td>状态: ${docker.state} | ID: ${docker.id || '-'}</td>
                        <td><span class="${statusClass}">${docker.state}</span></td>
                    </tr>
                `;
            });
        }
        
        html += `
                </table>
            </div>
        `;
    });
    
    content.innerHTML = html;
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
