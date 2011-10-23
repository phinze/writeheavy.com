desc "push site to server"
task :publish => :generate do
  sh "rsync -avzP --delete _site/* phinze.com:writeheavy.com/"
end

desc 'regenerate site with jekyll'
task :generate do
  sh "jekyll --pygments"
end
