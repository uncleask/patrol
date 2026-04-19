// 主脚本 - Patrol 系统巡检报告查看

// 当前时间显示
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

// 加载报告列表
function loadReportList() {
    const reportList = document.getElementById('report-list');
    reportList.innerHTML = '<li>加载中...</li>';
    
    // 模拟加载报告列表
    // 实际项目中，这里应该通过 AJAX 请求获取报告列表
    setTimeout(() => {
        // 模拟报告数据
        const reports = [
            {
                id: '1',
                name: 'patrol_report_20260419_163626.json',
                time: '2026-04-19 16:36:26',
                serverCount: 1
            },
            {
                id: '2',
                name: 'patrol_report_20260419_163608.json',
                time: '2026-04-19 16:36:08',
                serverCount: 1
            }
        ];
        
        reportList.innerHTML = '';
        
        reports.forEach(report => {
            const li = document.createElement('li');
            li.textContent = `${report.time} (${report.serverCount} 台服务器)`;
            li.dataset.reportName = report.name;
            li.addEventListener('click', () => {
                // 移除其他项的 active 类
                document.querySelectorAll('#report-list li').forEach(item => {
                    item.classList.remove('active');
                });
                // 添加当前项的 active 类
                li.classList.add('active');
                // 加载报告内容
                loadReportContent(report.name);
            });
            reportList.appendChild(li);
        });
        
        // 默认加载第一个报告
        if (reports.length > 0) {
            reportList.firstChild.click();
        }
    }, 500);
}

// 加载报告内容
function loadReportContent(reportName) {
    const reportContent = document.getElementById('report-content');
    reportContent.innerHTML = '<div class="loading"><p>加载报告中...</p></div>';
    
    // 模拟加载报告内容
    // 实际项目中，这里应该通过 AJAX 请求获取报告内容
    setTimeout(() => {
        // 模拟报告数据
        const reportData = {
            timestamp: '2026-04-19T16:36:26',
            servers: [
                {
                    alias: 'local-server',
                    ip: '127.0.0.1',
                    groups: 'local web',
                    results: [
                        {
                            name: 'cpu_usage',
                            value: '10.5',
                            status: 'normal'
                        },
                        {
                            name: 'memory_usage',
                            value: '45.2',
                            status: 'normal'
                        },
                        {
                            name: 'disk_usage',
                            value: '65.8',
                            status: 'normal'
                        },
                        {
                            name: 'process_count',
                            value: '120',
                            status: 'normal'
                        },
                        {
                            name: 'docker_containers',
                            value: '0',
                            status: 'normal'
                        },
                        {
                            name: 'docker_status',
                            value: '0',
                            status: 'normal'
                        }
                    ]
                }
            ]
        };
        
        // 渲染报告内容
        renderReport(reportData);
    }, 500);
}

// 渲染报告
function renderReport(reportData) {
    const reportContent = document.getElementById('report-content');
    
    let html = `
        <div class="report-summary">
            <h2>报告摘要</h2>
            <p>生成时间: ${new Date(reportData.timestamp).toLocaleString('zh-CN')}</p>
            <p>巡检服务器数量: ${reportData.servers.length}</p>
        </div>
    `;
    
    reportData.servers.forEach(server => {
        html += `
            <div class="server">
                <h3>${server.alias} (${server.ip})</h3>
                <div class="server-info">
                    <p>所属组: ${server.groups}</p>
                </div>
                <div class="checks">
        `;
        
        server.results.forEach(check => {
            html += `
                <div class="check-item ${check.status}">
                    <strong>${check.name}</strong>
                    <div class="value">${check.value}</div>
                    <span class="status">${check.status}</span>
                </div>
            `;
        });
        
        html += `
                </div>
            </div>
        `;
    });
    
    reportContent.innerHTML = html;
}

// 刷新功能
function refresh() {
    loadReportList();
}

// 初始化
function init() {
    // 更新当前时间
    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);
    
    // 加载报告列表
    loadReportList();
    
    // 绑定刷新按钮
    document.getElementById('refresh-btn').addEventListener('click', refresh);
}

// 页面加载完成后初始化
window.addEventListener('DOMContentLoaded', init);
