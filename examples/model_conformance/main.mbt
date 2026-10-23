///|
fn main raise {
  // A BPMN choice allows automatic OR manual approval, not both.
  let xml =
    #|<definitions xmlns="http://www.omg.org/spec/BPMN/20100524/MODEL" targetNamespace="urn:lens">
    #|<process id="approval" isExecutable="false"><startEvent id="s"/><exclusiveGateway id="split"/>
    #|<task id="a" name="automatic"/><task id="b" name="manual"/><exclusiveGateway id="join"/><endEvent id="e"/>
    #|<sequenceFlow id="f0" sourceRef="s" targetRef="split"/><sequenceFlow id="f1" sourceRef="split" targetRef="a"/>
    #|<sequenceFlow id="f2" sourceRef="split" targetRef="b"/><sequenceFlow id="f3" sourceRef="a" targetRef="join"/>
    #|<sequenceFlow id="f4" sourceRef="b" targetRef="join"/><sequenceFlow id="f5" sourceRef="join" targetRef="e"/>
    #|</process></definitions>
  let model = @lens.parse_bpmn(xml)
  let net = model.to_petri_net()
  let single = @lens.CaseTrace::new("good", [
    @lens.LogEvent::new("g", "good", "manual", 0L, 1L),
  ])
  let double = @lens.CaseTrace::new("bad", [
    @lens.LogEvent::new("b1", "bad", "automatic", 0L, 1L),
    @lens.LogEvent::new("b2", "bad", "manual", 2L, 3L),
  ])
  assert_eq(single.align_net(net).cost, 0)
  assert_eq(double.align_net(net).cost, 1)
  let restored = @lens.parse_bpmn(model.to_bpmn()).to_petri_net()
  assert_eq(double.align_net(restored).cost, 1)
  println(
    "BPMN approval: exclusive choice preserved; illegal double approval costs 1",
  )
  println(@lens.model_alignment_to_json(double.align_net(net)).stringify())
}
