// inferno module
import {render} from 'inferno';

// routing modules
import { Router, Route } from 'inferno-router';
import createBrowserHistory from 'history/createBrowserHistory';

// app components
import App from './App';
import Editor from './Editor';

if (module.hot) {
    require('inferno-devtools');
}

const history = createBrowserHistory();
window.browserHistory = history;

const routes = (
	<Router history={ history }>
		<Route component={ App }>
			<Route path="/edit" component={ Editor } />
		</Route>
	</Router>
);

render(routes, document.getElementById('app'));

if (module.hot) {
    module.hot.accept()
}
