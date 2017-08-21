const webpack = require('webpack');

module.exports = {
	entry: './src/index.js',
	output: {
		path: __dirname + '/../built',
		filename: 'bundle.js',
		publicPath: '/'
	},
	resolve: {
	  extensions: ['.js', '.jsx']
	},
	//devtool: 'source-map',
	module: {
		loaders: [{
			test: /\.jsx?$/,
			loader: 'babel-loader'
		}, {
			test: /\.css$/,
			loader: "style-loader!css-loader"
		}]
	},
	devServer: {
		contentBase: './',
		port: 8080,
		noInfo: false,
		hot: true,
		inline: true,
		proxy: {
			'/': {
				bypass: function (req, res, proxyOptions) {
					return '/public/index.html';
				}
			}
		}
	},
	plugins: [
		new webpack.HotModuleReplacementPlugin()
	]
};
