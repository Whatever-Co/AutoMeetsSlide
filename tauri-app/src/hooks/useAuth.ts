import { useEffect } from 'react';
import { useAppStore } from '../store/appStore';
import { useSidecar } from './useSidecar';

export function useAuth() {
  const { isAuthenticated, setIsAuthenticated } = useAppStore();
  const { checkAuth, login } = useSidecar();

  useEffect(() => {
    // Check auth on mount
    checkAuth();
  }, []);

  const handleLogin = async () => {
    return await login();
  };

  const handleLogout = () => {
    // For now, just reset the state
    // A proper logout would clear the stored credentials
    setIsAuthenticated(false);
  };

  return {
    isAuthenticated,
    isLoading: isAuthenticated === null,
    login: handleLogin,
    logout: handleLogout,
  };
}
