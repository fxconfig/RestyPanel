// API 统一请求服务模块

// API配置
const API_CONFIG = {
    baseURL: '/asd1239axasd/api',
    timeout: 10000
};

// 创建 axios 实例
const api = axios.create({
    baseURL: '/asd1239axasd/api',
    timeout: 10000,
    headers: {
        'Content-Type': 'application/json',
    }
});

// 请求拦截器 - 添加认证 token
api.interceptors.request.use(config => {
    const token = localStorage.getItem('RestyPanel_token');
    if (token) {
        config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
});

// 响应拦截器 - 处理认证错误
api.interceptors.response.use(
    response => response,
    error => {
        if (error.response?.status === 401) {
            // Token 过期或无效，清除并重新登录
            localStorage.removeItem('RestyPanel_token');
            window.location.reload();
        }
        return Promise.reject(error);
    }
);

// JWT Token管理工具
const TokenManager = {
    getToken() {
        return localStorage.getItem('RestyPanel_token');
    },
    
    setToken(token) {
        localStorage.setItem('RestyPanel_token', token);
        api.defaults.headers.common['Authorization'] = `Bearer ${token}`;
    },
    
    removeToken() {
        localStorage.removeItem('RestyPanel_token');
        delete api.defaults.headers.common['Authorization'];
    },
    
    isValidToken() {
        const token = this.getToken();
        if (!token) return false;
        
        try {
            // 解析JWT token检查过期时间
            const payload = JSON.parse(atob(token.split('.')[1]));
            // console.log('Token payload:', payload);
            
            // 检查token是否过期 (exp字段是Unix时间戳)
            const currentTime = Math.floor(Date.now() / 1000);
            const isValid = payload.exp > currentTime;
            
            console.log('Token validation:', {
                expires: new Date(payload.exp * 1000),
                current: new Date(currentTime * 1000),
                isValid
            });
            
            return isValid;
        } catch (e) {
            console.error('Token validation error:', e);
            return false;
        }
    }
};

// 统一API服务
const ApiService = {
    // 基础请求方法
    async request(method, url, data = null, options = {}) {
        try {
            const config = {
                method,
                url,
                headers: {
                    'Content-Type': 'application/json',
                    ...options.headers
                },
                ...options
            };
            
            if (data) {
                config.data = data;
            }
            
            const response = await api(config);
            return response.data;
        } catch (error) {
            console.error('API Error:', error);
            // 如果是401错误，清除token
            if (error.response?.status === 401) {
                TokenManager.removeToken();
                window.location.reload();
            }
            throw error.response?.data || { message: 'Network Error' };
        }
    },

    // GET 请求
    async get(url, options = {}) {
        return this.request('GET', url, null, options);
    },

    // POST 请求
    async post(url, data, options = {}) {
        return this.request('POST', url, data, options);
    },

    // PUT 请求
    async put(url, data, options = {}) {
        return this.request('PUT', url, data, options);
    },

    // DELETE 请求
    async delete(url, options = {}) {
        return this.request('DELETE', url, null, options);
    },

    // 认证相关API
    auth: {
        async login(credentials) {
            return ApiService.post('/auth/login', credentials);
        },

        async logout() {
            return ApiService.post('/auth/logout');
        },

        async profile() {
            return ApiService.get('/auth/profile');
        }
    },

    // 系统状态API
    status: {
        async get() {
            return ApiService.get('/status');
        }
    },

    // Upstream管理API
    upstreams: {
        async list() {
            return ApiService.get('/upstreams');
        },

        async create(data) {
            return ApiService.post('/upstreams', data);
        },

        async update(id, data) {
            return ApiService.put(`/upstreams/${id}`, data);
        },

        async delete(id) {
            return ApiService.delete(`/upstreams/${id}`);
        },

        async status() {
            return ApiService.get('/upstream/status');
        },

        async showConf() {
            return ApiService.get('/upstream/showconf');
        }
    },

    // 服务器管理API
    servers: {
        async list() {
            return ApiService.get('/servers');
        },

        async create(data) {
            return ApiService.post('/servers', data);
        },

        async update(id, data) {
            return ApiService.put(`/servers/${id}`, data);
        },

        async delete(id) {
            return ApiService.delete(`/servers/${id}`);
        }
    },

    // WAF管理API
    waf: {
        async getRules() {
            return ApiService.get('/waf/rules');
        },

        async createRule(data) {
            return ApiService.post('/waf/rules', data);
        },

        async updateRule(id, data) {
            return ApiService.put(`/waf/rules/${id}`, data);
        },

        async deleteRule(id) {
            return ApiService.delete(`/waf/rules/${id}`);
        }
    },

    // 系统设置API
    settings: {
        async get() {
            return ApiService.get('/settings');
        },

        async update(data) {
            return ApiService.put('/settings', data);
        },
        
        // 获取路径设置
        async getPaths() {
            return ApiService.get('/admin/settings/paths');
        },
        
        // 更新路径设置
        async updatePaths(data) {
            return ApiService.put('/admin/settings/paths', data);
        }
    }
};

// 导出服务
window.ApiService = ApiService;
window.TokenManager = TokenManager;
window.api = api; 