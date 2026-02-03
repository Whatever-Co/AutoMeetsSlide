import { useAppStore } from './store/appStore';
import { LoginScreen } from './components/LoginScreen';
import { MainApp } from './components/MainApp';
import './styles/index.css';

function App() {
  const { isAuthenticated } = useAppStore();

  // Show login screen if not authenticated (including loading state)
  if (!isAuthenticated) {
    return <LoginScreen />;
  }

  // Show main app when authenticated
  return <MainApp />;
}

export default App;
