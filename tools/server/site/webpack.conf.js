const webpack = require('webpack');
const path = require('path');

module.exports = {
  output: {
		path: path.join(__dirname, "/../built"),
		filename: "bundle.js"
	},

  module: {
         rules: [
             {
                 test: /\.jsx?$/,
                 loader: 'babel-loader',
                 options: {
                   babelrc: path.join(__dirname, './babelrc')
                 },
                 //include: path.join(__dirname, './src')
             }, {
          			test: /\.css$/,
          			loader: "style-loader!css-loader"
          	 }
         ]
     },

     resolve: {
         extensions: ['.web.js', '.mjs', '.js', '.json', '.web.jsx', '.jsx', '.css'],
         modules: [ 'node_modules' ]
     },
};
