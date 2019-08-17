{opts, conns} = OptionParser.parse(
    System.argv(),
    strict: [
      system: :integer,
      component: :integer,
    ],
    aliases: [
      s: :system,
      c: :component
    ]
  )

  MAVLink.Router.start_link(conns, opts)
