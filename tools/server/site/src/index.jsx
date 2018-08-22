// inferno module
import * as Inferno from 'inferno';

// routing modules
import { BrowserRouter, Route } from 'inferno-router';
//import createBrowserHistory from 'history/createBrowserHistory';

// app components
import Editor from './Editor';

const routes = (
	<BrowserRouter>
    <div>
			<div>
				<Route path="/edit" component={ Editor } />
			</div>
		</div>
	</BrowserRouter>
);

Inferno.render(routes, document.getElementById('app'));
