import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';

import { StaffAuthProvider } from './auth/StaffAuth';
import { App } from './App';
import './styles.css';

const root = document.getElementById('root');
if (root === null) {
  throw new Error('root element missing');
}

createRoot(root).render(
  <StrictMode>
    <BrowserRouter>
      <StaffAuthProvider>
        <App />
      </StaffAuthProvider>
    </BrowserRouter>
  </StrictMode>,
);
