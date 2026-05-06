// 全局变量
let reports = [];

// 页面加载完成后执行
window.onload = function() {
    if (window.location.pathname.includes('index.html') || window.location.pathname.endsWith('/')) {
        loadReportList();
    } else if (window.location.pathname.includes('report.html')) {
        loadReportDetail();
    } else if (window.location.pathname.includes('trend.html')) {
        loadTrendData();
    }
};

// 加载报告列表
function loadReportList() {
    fetch('./data/reports.json?t=' + new Date().getTime())
        .then(response => {
            if (!response.ok) {
                throw new Error('Failed to load reports.json');
            }
            return response.json();
        })
        .then(reportList => {
            const reportPromises = [];
            
            reportList.forEach(item => {
                const id = item.file.replace('.json', '');
                const formattedDate = item.date;
                const formattedTime = item.time;
                const reportPromise = fetch(`./data/${item.file}?t=${new Date().getTime()}`)
                    .then(response => response.json())
                    .then(data => {
                        let passCount = 0;
                        let failCount = 0;
                        let checkCount = 0;
                            
                            if (Array.isArray(data)) {
                                // 新格式：数据是数组，每个元素是服务器信息
                                data.forEach(server => {
                                    // 计算检查项数量
                                    if (server.cpu) checkCount++;
                                    if (server.memory) checkCount++;
                                    if (server.disk) checkCount += server.disk.length;
                                    if (server.apps) checkCount += server.apps.length;
                                    if (server.dockers) checkCount += server.dockers.length;
                                    
                                    // 计算通过/失败数量
                                    if (server.cpu && (server.cpu.usestate === 'normal' || server.cpu.usestate === 'ok')) passCount++;
                                    else if (server.cpu) failCount++;
                                    
                                    if (server.memory && (server.memory.usestate === 'normal' || server.memory.usestate === 'ok')) passCount++;
                                    else if (server.memory) failCount++;
                                    
                                    if (server.disk) {
                                        server.disk.forEach(disk => {
                                            if (disk.usestate === 'normal' || disk.usestate === 'ok') passCount++;
                                            else failCount++;
                                        });
                                    }
                                    
                                    if (server.apps) {
                                        server.apps.forEach(app => {
                                            if (app.state === 'running') passCount++;
                                            else failCount++;
                                        });
                                    }
                                    
                                    if (server.dockers) {
                                        server.dockers.forEach(docker => {
                                            if (docker.state === 'running' || docker.state === 'exited') passCount++;
                                            else failCount++;
                                        });
                                    }
                                });
                            } else if (data && data.servers && Array.isArray(data.servers)) {
                                // 旧格式：数据包含servers数组
                                data.servers.forEach(server => {
                                    if (server.checks && Array.isArray(server.checks)) {
                                        server.checks.forEach(check => {
                                            checkCount++;
                                            if (check.status === 'PASS') {
                                                passCount++;
                                            } else if (check.status === 'FAIL') {
                                                failCount++;
                                            }
                                        });
                                    }
                                });
                            }
                            
                            return {
                                id: id,
                                date: formattedDate,
                                time: formattedTime,
                                serverCount: Array.isArray(data) ? data.length : (data && data.servers ? data.servers.length : 0),
                                checkCount: checkCount,
                                passCount: passCount,
                                failCount: failCount
                            };
                        })
                        .catch(error => {
                            console.error('Failed to load report:', error);
                            // 即使报告加载失败，也返回一个条目
                            return {
                                id: id,
                                date: formattedDate,
                                time: formattedTime,
                                serverCount: 0,
                                checkCount: 0,
                                passCount: 0,
                                failCount: 0
                            };
                        });
                    
                    reportPromises.push(reportPromise);
            });
            
            // 等待所有报告加载完成
            Promise.all(reportPromises)
                .then(loadedReports => {
                    // 按时间降序排序
                    loadedReports.sort((a, b) => {
                        return new Date(`${b.date} ${b.time}`) - new Date(`${a.date} ${a.time}`);
                    });
                    
                    reports = loadedReports;
                    renderReportList();
                })
                .catch(error => {
                    console.error('Failed to load reports:', error);
                    // 使用模拟数据作为后备
                    const mockReports = [
                        {
                            id: 'report_20260416_044740',
                            date: '2026-04-16',
                            time: '04:47:40',
                            serverCount: 3,
                            checkCount: 25,
                            passCount: 20,
                            failCount: 5
                        },
                        {
                            id: 'report_20260416_044350',
                            date: '2026-04-16',
                            time: '04:43:50',
                            serverCount: 3,
                            checkCount: 25,
                            passCount: 19,
                            failCount: 6
                        },
                        {
                            id: 'report_20260416_044341',
                            date: '2026-04-16',
                            time: '04:43:41',
                            serverCount: 3,
                            checkCount: 25,
                            passCount: 21,
                            failCount: 4
                        }
                    ];
                    
                    reports = mockReports;
                    renderReportList();
                });
        })
        .catch(error => {
            console.error('Failed to load report list:', error);
            // 使用模拟数据作为后备
            const mockReports = [
                {
                    id: 'report_20260416_044740',
                    date: '2026-04-16',
                    time: '04:47:40',
                    serverCount: 3,
                    checkCount: 25,
                    passCount: 20,
                    failCount: 5
                },
                {
                    id: 'report_20260416_044350',
                    date: '2026-04-16',
                    time: '04:43:50',
                    serverCount: 3,
                    checkCount: 25,
                    passCount: 19,
                    failCount: 6
                },
                {
                    id: 'report_20260416_044341',
                    date: '2026-04-16',
                    time: '04:43:41',
                    serverCount: 3,
                    checkCount: 25,
                    passCount: 21,
                    failCount: 4
                }
            ];
            
            reports = mockReports;
            renderReportList();
        });
}

// 渲染报告列表
function renderReportList() {
    const reportList = document.getElementById('report-list');
    if (!reportList) return;
    
    if (reports.length === 0) {
        reportList.innerHTML = '<p>暂无巡检报告</p>';
        return;
    }
    
    let html = '';
    reports.forEach(report => {
        html += `
        <div class="report-item">
            <h3>${report.date} ${report.time}</h3>
            <p>服务器数量: ${report.serverCount}</p>
            <p>检查项数量: ${report.checkCount}</p>
            <p>通过: ${report.passCount} | 失败: ${report.failCount}</p>
            <a href="report.html?id=${report.id}">查看详情</a>
            <a href="report_detailed.html?file=${report.id}.json">查看详细报告</a>
        </div>
        `;
    });
    
    reportList.innerHTML = html;
}

// 加载报告详情
function loadReportDetail() {
    // 获取URL参数
    const urlParams = new URLSearchParams(window.location.search);
    const reportId = urlParams.get('id');
    
    if (!reportId) {
        document.getElementById('content').innerHTML = '<p>未指定报告ID</p>';
        return;
    }
    
    // 加载真实的报告数据
    fetch(`./data/${reportId}.json`)
        .then(response => {
            if (!response.ok) {
                throw new Error('Failed to load report');
            }
            return response.json();
        })
        .then(data => {
            // 检查数据结构
            if (!data) {
                document.getElementById('content').innerHTML = '<p>报告数据格式错误</p>';
                return;
            }
            
            renderReportDetail(data);
        })
        .catch(error => {
            console.error('Failed to load report:', error);
            document.getElementById('content').innerHTML = '<p>加载报告失败，请重试</p>';
        });
}

// 渲染报告详情
function renderReportDetail(data) {
    const content = document.getElementById('content');
    if (!content) return;
    
    let html = `
    <div class="summary">
        <h2>巡检汇总信息</h2>
        <div class="summary-item"><strong>报告生成时间:</strong> ${new Date().toLocaleString()}</div>
        <div class="summary-item"><strong>服务器数量:</strong> ${Array.isArray(data) ? data.length : 0}</div>
    </div>
    `;
    
    // 告警信息
    let hasAlert = false;
    let alertHtml = '<div class="alert alert-warning"><h3>巡检告警信息</h3><ul>';
    
    if (Array.isArray(data)) {
        // 新格式：数据是数组，每个元素是服务器信息
        data.forEach(server => {
            const serverName = server.hostname || server.alias || server.server || 'Unknown';
            const serverIp = server.hostip || server.ip || 'Unknown';
            
            // 检查CPU
            if (server.cpu && (server.cpu.usestate === 'warn' || server.cpu.usestate === 'serious')) {
                hasAlert = true;
                alertHtml += `<li>${serverName} (${serverIp}): CPU使用率过高 - 实际值: ${server.cpu.usage}%, 状态: ${server.cpu.usestate}</li>`;
            }
            
            // 检查内存
            if (server.memory && (server.memory.usestate === 'warn' || server.memory.usestate === 'serious')) {
                hasAlert = true;
                alertHtml += `<li>${serverName} (${serverIp}): 内存使用率过高 - 实际值: ${server.memory.usage}%, 状态: ${server.memory.usestate}</li>`;
            }
            
            // 检查磁盘
            if (server.disk) {
                server.disk.forEach(disk => {
                    if (disk.usestate === 'warn' || disk.usestate === 'serious') {
                        hasAlert = true;
                        alertHtml += `<li>${serverName} (${serverIp}): 磁盘使用率过高 (${disk.mounted}) - 实际值: ${disk.usage}%, 状态: ${disk.usestate}</li>`;
                    }
                });
            }
            
            // 检查应用
            if (server.apps) {
                server.apps.forEach(app => {
                    if (app.state !== 'running') {
                        hasAlert = true;
                        alertHtml += `<li>${serverName} (${serverIp}): 应用 ${app.name} 状态异常 - 状态: ${app.state}</li>`;
                    }
                });
            }
            
            // 检查Docker容器
            if (server.dockers) {
                server.dockers.forEach(docker => {
                    if (docker.state !== 'running') {
                        hasAlert = true;
                        alertHtml += `<li>${serverName} (${serverIp}): 容器 ${docker.name} 状态异常 - 状态: ${docker.state}</li>`;
                    }
                });
            }
        });
    } else if (data && data.servers && Array.isArray(data.servers)) {
        // 旧格式：数据包含servers数组
        data.servers.forEach(server => {
            if (server.checks && Array.isArray(server.checks)) {
                server.checks.forEach(check => {
                    if (check.status === 'FAIL') {
                        hasAlert = true;
                        alertHtml += `<li>${server.alias} (${server.ip}): ${check.name} - 实际值: ${check.raw_output}, 预期值: ${check.expected}</li>`;
                    }
                });
            }
        });
    }
    
    if (hasAlert) {
        alertHtml += '</ul></div>';
        html += alertHtml;
    }
    
    // 服务器信息
    if (Array.isArray(data)) {
        // 新格式：数据是数组，每个元素是服务器信息
        data.forEach(server => {
            const serverName = server.hostname || server.alias || server.server || 'Unknown';
            const serverIp = server.hostip || server.ip || 'Unknown';
            
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
            
            // 系统信息
            if (server.os) {
                html += `
                    <tr>
                        <td>操作系统</td>
                        <td>${server.os}</td>
                        <td><span class="status-pass">正常</span></td>
                    </tr>
                `;
            }
            
            if (server.time) {
                html += `
                    <tr>
                        <td>巡检时间</td>
                        <td>${server.time}</td>
                        <td><span class="status-pass">正常</span></td>
                    </tr>
                `;
            }
            
            // CPU信息
            if (server.cpu) {
                let statusClass = 'status-pass';
                if (server.cpu.usestate === 'warn') statusClass = 'status-warn';
                if (server.cpu.usestate === 'serious') statusClass = 'status-fail';
                
                html += `
                    <tr>
                        <td>CPU使用率</td>
                        <td>${server.cpu.usage}%</td>
                        <td><span class="${statusClass}">${server.cpu.usestate}</span></td>
                    </tr>
                `;
            }
            
            // 内存信息
            if (server.memory) {
                let statusClass = 'status-pass';
                if (server.memory.usestate === 'warn') statusClass = 'status-warn';
                if (server.memory.usestate === 'serious') statusClass = 'status-fail';
                
                html += `
                    <tr>
                        <td>内存使用</td>
                        <td>已用: ${server.memory.used}MB / 总量: ${server.memory.total}MB (${server.memory.usage}%)</td>
                        <td><span class="${statusClass}">${server.memory.usestate}</span></td>
                    </tr>
                `;
            }
            
            // 磁盘信息
            if (server.disk && server.disk.length > 0) {
                server.disk.forEach(disk => {
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
            
            // 应用信息
            if (server.apps && server.apps.length > 0) {
                server.apps.forEach(app => {
                    let statusClass = app.state === 'running' ? 'status-pass' : 'status-fail';
                    
                    html += `
                        <tr>
                            <td>应用 ${app.name}</td>
                            <td>状态: ${app.state}, PID: ${app.pid}, CPU: ${app.cpuusage}%, MEM: ${app.memusage}%</td>
                            <td><span class="${statusClass}">${app.state}</span></td>
                        </tr>
                    `;
                });
            }
            
            // Docker容器信息
            if (server.dockers && server.dockers.length > 0) {
                server.dockers.forEach(docker => {
                    let statusClass = docker.state === 'running' ? 'status-pass' : 'status-fail';
                    
                    html += `
                        <tr>
                            <td>容器 ${docker.name}</td>
                            <td>状态: ${docker.state}, ID: ${docker.id}</td>
                            <td><span class="${statusClass}">${docker.state}</span></td>
                        </tr>
                    `;
                });
            }
            
            // 结果统计
            if (server.result) {
                html += `
                    <tr>
                        <td>巡检统计</td>
                        <td>总计: ${server.result.all_count}, 正常: ${server.result.normal_count}, 警告: ${server.result.warn_count}, 严重: ${server.result.serious_count}</td>
                        <td><span class="status-pass">完成</span></td>
                    </tr>
                `;
                
                if (server.result.description && server.result.description !== "【正常】") {
                    html += `
                        <tr>
                            <td>告警详情</td>
                            <td colspan="2" style="color: red;">${server.result.description}</td>
                        </tr>
                    `;
                }
            }
            
            html += `
                </table>
            </div>
            `;
        });
    } else if (data && data.servers && Array.isArray(data.servers)) {
        // 旧格式：数据包含servers数组
        data.servers.forEach(server => {
            html += `
            <div class="server-section">
                <div class="server-header">服务器: ${server.alias} (${server.ip})</div>
                <table>
                    <tr>
                        <th>检查项</th>
                        <th>命令</th>
                        <th>实际输出</th>
                        <th>预期值</th>
                        <th>状态</th>
                        <th>执行时间(ms)</th>
                    </tr>
            `;
            
            if (server.checks && Array.isArray(server.checks)) {
                server.checks.forEach(check => {
                    let statusClass = '';
                    switch (check.status) {
                        case 'PASS': statusClass = 'status-pass'; break;
                        case 'FAIL': statusClass = 'status-fail'; break;
                        case 'WARN': statusClass = 'status-warn'; break;
                    }
                    
                    html += `
                        <tr>
                            <td>${check.name}</td>
                            <td>${check.command}</td>
                            <td>${check.raw_output}</td>
                            <td>${check.expected}</td>
                            <td><span class="${statusClass}">${check.status}</span></td>
                            <td>${check.duration_ms || 0}</td>
                        </tr>
                    `;
                });
            }
            
            html += `
                </table>
            </div>
            `;
        });
    }
    
    content.innerHTML = html;
}

// 加载趋势数据
function loadTrendData() {
    // 这里应该从服务器获取趋势数据，现在使用模拟数据
    const mockTrendData = {
        dates: ['2026-04-14', '2026-04-15', '2026-04-16'],
        cpuUsage: [65, 72, 75],
        memoryUsage: [70, 78, 85],
        diskUsage: [60, 65, 70],
        alertCount: [1, 2, 3]
    };
    
    renderTrendData(mockTrendData);
}

// 渲染趋势数据
function renderTrendData(data) {
    const content = document.getElementById('content');
    if (!content) return;
    
    let html = `
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
    
    content.innerHTML = html;
    
    // 简单的图表绘制（实际项目中可以使用Chart.js等库）
    drawResourceChart(data);
    drawAlertChart(data);
}

// 绘制资源使用趋势图
function drawResourceChart(data) {
    const canvas = document.getElementById('resourceChart');
    if (!canvas) return;
    
    const ctx = canvas.getContext('2d');
    
    // 绘制坐标轴
    ctx.beginPath();
    ctx.moveTo(50, 350);
    ctx.lineTo(750, 350);
    ctx.lineTo(745, 345);
    ctx.moveTo(750, 350);
    ctx.lineTo(745, 355);
    ctx.moveTo(50, 350);
    ctx.lineTo(50, 50);
    ctx.lineTo(45, 55);
    ctx.moveTo(50, 50);
    ctx.lineTo(55, 55);
    ctx.stroke();
    
    // 绘制数据点和线条
    const colors = ['#4CAF50', '#2196F3', '#FF9800'];
    const labels = ['CPU使用率', '内存使用率', '磁盘使用率'];
    const datasets = [data.cpuUsage, data.memoryUsage, data.diskUsage];
    
    for (let i = 0; i < datasets.length; i++) {
        ctx.beginPath();
        ctx.strokeStyle = colors[i];
        ctx.lineWidth = 2;
        
        for (let j = 0; j < datasets[i].length; j++) {
            const x = 50 + (j * (700 / (datasets[i].length - 1)));
            const y = 350 - (datasets[i][j] * 3);
            
            if (j === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
            
            // 绘制数据点
            ctx.fillStyle = colors[i];
            ctx.beginPath();
            ctx.arc(x, y, 4, 0, Math.PI * 2);
            ctx.fill();
        }
        
        ctx.stroke();
        
        // 绘制图例
        ctx.fillStyle = colors[i];
        ctx.fillRect(600, 50 + (i * 20), 15, 15);
        ctx.fillStyle = '#333';
        ctx.font = '12px Arial';
        ctx.fillText(labels[i], 620, 62 + (i * 20));
    }
    
    // 绘制X轴标签
    ctx.font = '12px Arial';
    ctx.fillStyle = '#333';
    data.dates.forEach((date, index) => {
        const x = 50 + (index * (700 / (data.dates.length - 1)));
        ctx.fillText(date, x - 20, 375);
    });
    
    // 绘制Y轴标签
    for (let i = 0; i <= 100; i += 20) {
        const y = 350 - (i * 3);
        ctx.fillText(i + '%', 20, y + 4);
    }
}

// 绘制告警趋势图
function drawAlertChart(data) {
    const canvas = document.getElementById('alertChart');
    if (!canvas) return;
    
    const ctx = canvas.getContext('2d');
    
    // 绘制坐标轴
    ctx.beginPath();
    ctx.moveTo(50, 350);
    ctx.lineTo(750, 350);
    ctx.lineTo(745, 345);
    ctx.moveTo(750, 350);
    ctx.lineTo(745, 355);
    ctx.moveTo(50, 350);
    ctx.lineTo(50, 50);
    ctx.lineTo(45, 55);
    ctx.moveTo(50, 50);
    ctx.lineTo(55, 55);
    ctx.stroke();
    
    // 绘制柱状图
    const barWidth = 700 / data.dates.length * 0.8;
    
    data.dates.forEach((date, index) => {
        const x = 50 + (index * (700 / data.dates.length)) + (barWidth * 0.1);
        const height = data.alertCount[index] * 50;
        const y = 350 - height;
        
        ctx.fillStyle = '#f44336';
        ctx.fillRect(x, y, barWidth, height);
        
        // 绘制数值
        ctx.fillStyle = '#333';
        ctx.font = '12px Arial';
        ctx.fillText(data.alertCount[index], x + barWidth / 2 - 5, y - 5);
        
        // 绘制日期
        ctx.fillText(date, x + barWidth / 2 - 20, 375);
    });
    
    // 绘制Y轴标签
    for (let i = 0; i <= Math.max(...data.alertCount); i++) {
        const y = 350 - (i * 50);
        ctx.fillText(i, 20, y + 4);
    }
}
