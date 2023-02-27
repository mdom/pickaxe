package App::pickaxe::LinkBrowser;
use Mojo::Base 'App::pickaxe::UI::Index', -signatures;

has [ 'links', 'api', 'config' ];

has helpbar    => "q:Quit";
has statusbar  => "pickaxe: Link Browser";

sub follow_link ( $self, $key ) {
    my $link = $self->links->[ $self->current_line ];
    if ( $link !~ /^http/ ) {
        my $page = $self->api->page( $link, -1 );
        if ( !$page ) {
            $self->message(qq{Can't find page "$link"});
            return;
        }
        App::pickaxe::Pager->new(
            config => $self->config,
            pages  => App::pickaxe::Pages->new->set( [$page] ),
            api    => $self->api
        )->run;
        return;
    }

    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $link ] );
}

sub run ( $self ) {
    $self->set_lines( @{ $self->links } );
    $self->next::method($self->config->keybindings);
}

1;
